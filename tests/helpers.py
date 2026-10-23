"""Shared helpers: Terraform outputs, Entra tokens, JWT claims, and a minimal MCP client.

Tokens are never printed or written anywhere except the MSAL cache in .out/.
"""

from __future__ import annotations

import base64
import functools
import json
import subprocess
from pathlib import Path

import httpx
import msal

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".out"
DATABRICKS_RESOURCE = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"


@functools.cache
def tf_outputs() -> dict:
    raw = subprocess.run(
        ["terraform", f"-chdir={ROOT / 'infra'}", "output", "-json"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return {k: v["value"] for k, v in json.loads(raw).items()}


def claims(token: str) -> dict:
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))


def az_token(resource: str, tenant_id: str) -> str:
    """Token from the az CLI, pinned to the tenant (the CLI can otherwise pick the home tenant)."""
    return subprocess.run(
        [
            "az", "account", "get-access-token",
            "--tenant", tenant_id,
            "--resource", resource,
            "--query", "accessToken",
            "-o", "tsv",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def _msal_app() -> tuple[msal.PublicClientApplication, msal.SerializableTokenCache, Path]:
    out = tf_outputs()
    OUT.mkdir(exist_ok=True)
    cache_path = OUT / "msal_cache.json"
    cache = msal.SerializableTokenCache()
    if cache_path.exists():
        cache.deserialize(cache_path.read_text())
    app = msal.PublicClientApplication(
        out["client_app_id"],
        authority=f"https://login.microsoftonline.com/{out['tenant_id']}",
        token_cache=cache,
    )
    return app, cache, cache_path


def user_token(scope: str | None = None, interactive: bool = False, prompt: str = "select_account") -> str:
    """User token for the gateway API, issued to the client app. Run `make login` once first."""
    scope = scope or tf_outputs()["gateway_scope"]
    app, cache, cache_path = _msal_app()
    result = None
    accounts = app.get_accounts()
    if accounts and prompt != "consent":
        result = app.acquire_token_silent([scope], account=accounts[0])
    if not result and interactive:
        result = app.acquire_token_interactive([scope], prompt=prompt)
    if cache.has_state_changed:
        cache_path.write_text(cache.serialize())
        cache_path.chmod(0o600)
    if not result or "access_token" not in result:
        detail = (result or {}).get("error_description", "no cached account; run `make login`")
        raise RuntimeError(f"Could not get a user token for {scope}: {detail}")
    return result["access_token"]


class McpClient:
    """Just enough MCP (streamable HTTP, JSON-RPC 2.0) to initialize, list, and call tools."""

    def __init__(self, url: str, token: str, timeout: float = 60.0):
        self.url = url
        self.http = httpx.Client(timeout=timeout)
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
        }
        self._id = 0

    def _post(self, method: str, params: dict | None = None, notify: bool = False) -> httpx.Response:
        body: dict = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if not notify:
            self._id += 1
            body["id"] = self._id
        return self.http.post(self.url, headers=self.headers, json=body)

    @staticmethod
    def _result(resp: httpx.Response) -> dict:
        resp.raise_for_status()
        if resp.headers.get("content-type", "").startswith("text/event-stream"):
            for line in resp.text.splitlines():
                if line.startswith("data:"):
                    msg = json.loads(line[5:])
                    if "result" in msg or "error" in msg:
                        return msg
            raise ValueError("no JSON-RPC response in event stream")
        return resp.json()

    def initialize(self) -> httpx.Response:
        resp = self._post(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "uga-tests", "version": "0.1"},
            },
        )
        if resp.status_code == 200 and (sid := resp.headers.get("mcp-session-id")):
            self.headers["Mcp-Session-Id"] = sid
        if resp.status_code == 200:
            self._post("notifications/initialized", notify=True)
        return resp

    def list_tools(self) -> list[dict]:
        return self._result(self._post("tools/list"))["result"]["tools"]

    def call_tool(self, name: str, arguments: dict) -> dict:
        return self._result(self._post("tools/call", {"name": name, "arguments": arguments}))
