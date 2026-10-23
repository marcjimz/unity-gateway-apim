"""End-to-end checks for the three flows. Each asserts the identity at the execution layer.

Flow #1  Databricks login -> Unity Gateway MCP (per-user OAuth) -> APIM -> OBO -> Graph      actor: user
Flow #2  Foundry agent -> APIM -> Databricks Foundation Models                              actor: Foundry project MI
Flow #3  Foundry/CLI login -> APIM -> OBO -> Databricks managed MCP (system.ai.dbsql)       actor: user
"""

import json
import subprocess

import httpx
import pytest

from tests.helpers import McpClient, claims

pytestmark = pytest.mark.e2e

def graph_mcp_name(out: dict) -> str:
    """Registered by databricks/setup.py as <catalog>.<schema>.<service>."""
    return f"uga_{out['apim_name'].split('-')[1]}.tools.graph"


def text_of(result: dict) -> str:
    return "".join(c.get("text", "") for c in result["result"].get("content", []))


def app_insights_hops(out: dict, minutes: int = 15) -> list[dict]:
    """identity-hop traces that APIM wrote (claims only)."""
    query = (
        f"traces | where timestamp > ago({minutes}m) and message startswith 'identity-hop' "
        "| project message | order by timestamp desc | take 50"
    )
    raw = subprocess.run(
        ["az", "monitor", "app-insights", "query", "--app", out["app_insights_app_id"],
         "--analytics-query", query, "-o", "json"],
        check=True, capture_output=True, text=True,
    ).stdout
    rows = json.loads(raw)["tables"][0]["rows"]
    return [json.loads(r[0].removeprefix("identity-hop ")) for r in rows]


# ---------- Flow #3

def dbsql_via_apim(out: dict, token: str) -> McpClient:
    url = f"{out['apim_gateway_url']}/databricks/mcp/ai-gateway/mcp-services/system.ai.dbsql"
    return McpClient(url, token)


def test_flow3_rejects_missing_token(out):
    resp = httpx.post(
        f"{out['apim_gateway_url']}/databricks/mcp/ai-gateway/mcp-services/system.ai.dbsql",
        json={"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
        timeout=30,
    )
    assert resp.status_code == 401


def test_flow3_rejects_non_mcp_paths(out, gateway_token):
    resp = httpx.get(
        f"{out['apim_gateway_url']}/databricks/mcp/api/2.0/clusters/list",
        headers={"Authorization": f"Bearer {gateway_token}"},
        timeout=30,
    )
    assert resp.status_code == 404


def test_flow3_sql_runs_as_the_user(out, gateway_token, databricks_token):
    mcp = dbsql_via_apim(out, gateway_token)
    assert mcp.initialize().status_code == 200
    tools = {t["name"]: t for t in mcp.list_tools()}
    assert "execute_sql" in tools
    result = mcp.call_tool("execute_sql", {"query": "SELECT current_user() AS me"})
    me = httpx.get(
        f"{out['databricks_host']}/api/2.0/preview/scim/v2/Me",
        headers={"Authorization": f"Bearer {databricks_token}"},
        timeout=30,
    ).json()["userName"]
    assert me.lower() in text_of(result).lower()


# ---------- Flow #1

def test_flow1_graph_tool_runs_as_the_user(out, databricks_token):
    """Called with the user's Databricks identity, exactly as the Databricks agent does."""
    url = f"{out['databricks_host']}/ai-gateway/mcp-services/{graph_mcp_name(out)}"
    mcp = McpClient(url, databricks_token)
    assert mcp.initialize().status_code == 200, "MCP service missing, or sign-in to the connection needed"
    assert {"get_my_profile", "list_my_groups", "find_user"} <= {t["name"] for t in mcp.list_tools()}
    result = mcp.call_tool("get_my_profile", {})
    assert claims(databricks_token)["oid"] in text_of(result)


# ---------- Flow #2

def test_flow2_rejects_user_tokens(out, databricks_token):
    """Only the Foundry project identity may use the model route, not end users directly."""
    resp = httpx.post(
        f"{out['apim_gateway_url']}/databricks/models/chat/completions",
        headers={"Authorization": f"Bearer {databricks_token}"},
        json={"model": "databricks-meta-llama-3-3-70b-instruct", "messages": [{"role": "user", "content": "hi"}]},
        timeout=30,
    )
    assert resp.status_code == 401


def test_flow2_foundry_agent_uses_databricks_model(out):
    pytest.importorskip("azure.ai.projects")
    from azure.ai.projects import AIProjectClient
    from azure.identity import AzureCliCredential

    project = AIProjectClient(
        endpoint=out["foundry_project_endpoint"],
        credential=AzureCliCredential(tenant_id=out["tenant_id"]),
    )
    openai = project.get_openai_client()
    conversation = openai.conversations.create()
    try:
        response = openai.responses.create(
            conversation=conversation.id,
            input="Reply with the single word: pong",
            extra_body={"agent_reference": {"name": "uga-databricks-agent", "type": "agent_reference"}},
        )
        assert "pong" in response.output_text.lower()
    finally:
        openai.conversations.delete(conversation_id=conversation.id)

    hops = [h for h in app_insights_hops(out) if h["api"] == "databricks-models"]
    assert hops, "no APIM trace for the model call yet (App Insights ingestion can lag a few minutes)"
    assert hops[0]["caller_appid"] == out["foundry_mi_app_id"]
