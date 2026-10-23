"""Phase 0: check every auth assumption before building the flows on top of it.

Each test maps to an F-number in tests/feasibility/RESULTS.md.
"""

import httpx
import pytest

from tests.helpers import DATABRICKS_RESOURCE, McpClient, az_token, claims

pytestmark = pytest.mark.feasibility


def databricks_me(host: str, token: str) -> httpx.Response:
    return httpx.get(
        f"{host}/api/2.0/preview/scim/v2/Me",
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )


# F1: every token is minted by the sandbox tenant.
@pytest.mark.parametrize(
    "resource",
    ["https://management.azure.com/", DATABRICKS_RESOURCE, "https://graph.microsoft.com"],
)
def test_f1_tokens_are_pinned_to_tenant(out, resource):
    assert claims(az_token(resource, out["tenant_id"]))["tid"] == out["tenant_id"]


# F2: the user's Entra claims map to their Databricks username (guest accounts included).
def test_f2_entra_user_maps_to_databricks_user(out, databricks_token):
    resp = databricks_me(out["databricks_host"], databricks_token)
    assert resp.status_code == 200, resp.text
    username = resp.json()["userName"].lower()
    c = claims(databricks_token)
    candidates = {str(c.get(k, "")).lower() for k in ("upn", "unique_name", "email", "preferred_username")}
    assert username in candidates, f"Databricks user {username!r} not in token claims"


# F3: a plain Entra token (audience Azure Databricks) is accepted by the Unity Gateway MCP endpoint.
# (The legacy /api/2.0/mcp/* endpoints need a separate workspace preview and aren't used.)
def test_f3_entra_token_on_managed_mcp(out, databricks_token):
    mcp = McpClient(out["databricks_host"] + "/ai-gateway/mcp-services/system.ai.dbsql", databricks_token)
    resp = mcp.initialize()
    assert resp.status_code == 200, resp.text
    assert "execute_sql" in {t["name"] for t in mcp.list_tools()}


# F5: the user can consent to the gateway scope without an admin (token issued with scp).
def test_f5_user_token_for_gateway_scope(out, gateway_token):
    c = claims(gateway_token)
    assert c["tid"] == out["tenant_id"]
    assert "mcp.invoke" in c.get("scp", "").split()
    assert c.get("azp") == out["client_app_id"]


# F10: APIM validates the user token, and rejects missing or wrong-audience tokens.
def test_f10_apim_validates_user_token(out, gateway_token, databricks_token):
    url = f"{out['apim_gateway_url']}/probe/whoami"
    assert httpx.get(url, timeout=30).status_code == 401
    wrong = httpx.get(url, headers={"Authorization": f"Bearer {databricks_token}"}, timeout=30)
    assert wrong.status_code == 401
    ok = httpx.get(url, headers={"Authorization": f"Bearer {gateway_token}"}, timeout=30)
    assert ok.status_code == 200, ok.text
    assert ok.json()["oid"] == claims(gateway_token)["oid"]


# F6: APIM performs OBO (managed identity as federated credential) and Databricks sees the same user.
def test_f6_apim_obo_to_databricks(out, gateway_token, databricks_token):
    resp = httpx.get(
        f"{out['apim_gateway_url']}/probe/obo-databricks",
        headers={"Authorization": f"Bearer {gateway_token}"},
        timeout=60,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["obo_oid"] == body["caller_oid"], "OBO token is for a different principal"
    assert body["databricks_status"] == 200, body
    expected = databricks_me(out["databricks_host"], databricks_token).json()["userName"]
    assert body["databricks_user"].lower() == expected.lower()


def test_f6_apim_obo_to_graph(out, gateway_token):
    resp = httpx.get(
        f"{out['apim_gateway_url']}/probe/obo-graph",
        headers={"Authorization": f"Bearer {gateway_token}"},
        timeout=60,
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["graph_status"] == 200, body
    assert body["graph_id"] == body["caller_oid"]


# F8: the Databricks-provided MCPs are visible (Unity Gateway preview enabled).
def test_f8_system_ai_mcp_services_listed(out, databricks_token):
    resp = httpx.get(
        f"{out['databricks_host']}/api/2.1/unity-catalog/mcp-services",
        params={"parent": "schemas/system.ai"},
        headers={"Authorization": f"Bearer {databricks_token}"},
        timeout=30,
    )
    assert resp.status_code == 200, resp.text
    names = {s["name"] for s in resp.json().get("mcp_services", [])}
    assert any(n.endswith("system.ai.dbsql") for n in names), names
