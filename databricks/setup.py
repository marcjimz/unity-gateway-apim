"""Post-provision Databricks setup (idempotent). Run after `make up`: `make databricks`.

Flow #1: registers the APIM Graph MCP server as a Unity Catalog MCP service.
  catalog uga_<suffix> / schema tools (created by Terraform, infra/catalog.tf)
  HTTP connection `graph_apim`  - OAuth User-to-Machine *per user* against Entra, so every Databricks user signs in
                                  once and the MCP calls carry that user's own Entra token (never a shared one).
  MCP service `graph`           - https://<workspace>/ai-gateway/mcp-services/uga_<suffix>.tools.graph

The connection is created through the REST API because the Terraform provider does not support OAuth U2M connections.
"""

from __future__ import annotations

import sys
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests.helpers import DATABRICKS_RESOURCE, az_token, tf_outputs  # noqa: E402

out = tf_outputs()
CATALOG = out["catalog"]
SCHEMA = "tools"
CONNECTION = "graph_apim"
MCP_SERVICE = "graph"

api = httpx.Client(
    base_url=out["databricks_host"],
    headers={"Authorization": f"Bearer {az_token(DATABRICKS_RESOURCE, out['tenant_id'])}"},
    timeout=60,
)


def ensure(get_path: str, create_path: str, body: dict, params: dict | None = None) -> dict:
    resp = api.get(get_path)
    if resp.status_code == 200:
        return resp.json()
    resp = api.post(create_path, json=body, params=params)
    if resp.status_code >= 400:
        sys.exit(f"POST {create_path} failed ({resp.status_code}): {resp.text}")
    return resp.json()


# The catalog and schema come from Terraform (infra/catalog.tf), on our own storage account.
if api.get(f"/api/2.1/unity-catalog/schemas/{CATALOG}.{SCHEMA}").status_code != 200:
    sys.exit(f"Schema {CATALOG}.{SCHEMA} not found: run `make up` first")

tenant = out["tenant_id"]
connection = ensure(
    f"/api/2.1/unity-catalog/connections/{CATALOG}.{SCHEMA}.{CONNECTION}",
    "/api/2.1/unity-catalog/connections",
    {
        "name": CONNECTION,
        "parent": f"schemas/{CATALOG}.{SCHEMA}",
        "connection_type": "HTTP",
        "comment": "APIM Graph MCP; each user signs in to Entra with their own account",
        "options": {
            "host": out["apim_gateway_url"],
            "port": "443",
            "base_path": "/graph-mcp/mcp",
            "client_id": out["client_app_id"],
            "client_secret": out["client_secret"],
            "authorization_endpoint": f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize",
            "token_endpoint": f"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token",
            "oauth_scope": f"{out['gateway_scope']} offline_access",
            "oauth_credential_exchange_method": "body_only",
        },
    },
)
if connection.get("credential_type") != "OAUTH_U2M_MAPPING":
    sys.exit(f"Connection is {connection.get('credential_type')}, expected per-user OAuth (OAUTH_U2M_MAPPING)")

ensure(
    f"/api/2.1/unity-catalog/mcp-services/{CATALOG}.{SCHEMA}.{MCP_SERVICE}",
    "/api/2.1/unity-catalog/mcp-services",
    {
        "comment": "Microsoft Graph via APIM, called as the signed-in user",
        "config": {"source_connection": {"name": f"connections/{CATALOG}.{SCHEMA}.{CONNECTION}"}},
    },
    params={"parent": f"schemas/{CATALOG}.{SCHEMA}", "mcp_service_id": MCP_SERVICE},
)

print(f"MCP service: {out['databricks_host']}/ai-gateway/mcp-services/{CATALOG}.{SCHEMA}.{MCP_SERVICE}")
print(f"Sign in once: Unity Gateway -> MCPs -> {CATALOG}.{SCHEMA}.{MCP_SERVICE} -> Login")
