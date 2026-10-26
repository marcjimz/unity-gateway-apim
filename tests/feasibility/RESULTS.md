# Feasibility results

Filled in by running `make test-feasibility` against a fresh `make up`. One row per assumption.
Last run: 2026-10-21, sandbox `uga-m2ld5`, centralus.

| # | Assumption | Result | Notes / fallback |
|---|---|---|---|
| F1 | All credentials pinned to the sandbox tenant | **Pass** | az tokens for ARM, Databricks and Graph, plus the Databricks account API, all from the sandbox tenant. Without `DATABRICKS_AZURE_TENANT_ID` the Databricks CLI sometimes minted home-tenant tokens. |
| F2 | Guest user's Entra claims map to the Databricks username | **Pass** | Guest tokens carry no `upn`; `email` / `unique_name` match the Databricks `userName`. |
| F3 | Plain Entra token accepted by managed MCP | **Pass** | `/ai-gateway/mcp-services/system.ai.dbsql` → 200, tool `execute_sql`. The legacy `/api/2.0/mcp/sql` endpoint needs a workspace preview and isn't used. |
| F4 | Federation-policy token exchange | **Not needed** | F3 passed, so APIM uses Entra OBO directly. |
| F5 | User consent (no admin) for gateway, Databricks, Graph scopes | **Pass** | A guest can user-consent. Bundled consent (`knownClientApplications`) is skipped when the client is pre-authorized, so `make login` consents to the gateway app directly. One resource per token request; Graph scopes go in `extra_scopes_to_consent`. App owners must be set explicitly. |
| F6 | APIM OBO using its managed identity as a federated credential | **Pass** | OBO tokens for Databricks (`user_impersonation`) and Graph carry the caller's `oid`; Databricks `scim/Me` and Graph `/me` return the same user. No secret in APIM. |
| F7 | Foundry project MI token accepted by Databricks | **Pass** | Token (audience Azure Databricks, `idtyp=app`) forwarded unchanged by APIM. The MI must be a workspace service principal with **workspace-access**; without it, 403. After granting it, Databricks' model gateway caches the 403 for about 5–10 min. Pay-per-token endpoints have no per-endpoint grants. APIM also drops `top_p` for Claude and normalizes streamed `usage` for Foundry's parser. |
| F8 | Unity Gateway MCPs available | **Pass** | `system.ai.*` MCP services are listed for the workspace. |
| F9 | Work IQ MCP usable in this tenant | _manual_ | Default is Graph REST exposed as MCP in APIM. |
| F10 | APIM v2 validates tokens; provisioning time | **Pass** | 401 with no token, a Databricks-audience token, or a user token on the model route; 200 with a gateway user token. StandardV2 plus the Databricks workspace took about 13 minutes. |
