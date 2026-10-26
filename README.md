# unity-gateway-apim

Azure API Management (APIM) in front of Azure Databricks and Microsoft Foundry, where the **signed-in Entra
user** is the identity that runs each request: models, tools, and data. No shared service principal acts for the user.

## What's here

| Folder | Contents |
|---|---|
| `infra/` | Terraform: resource group, APIM (v2), Foundry account + project, Databricks workspace + Unity Catalog metastore assignment, Entra app registrations |
| `apim/policies/` | APIM policies: token validation, On-Behalf-Of (OBO) exchange, identity logging |
| `databricks/` | Unity Catalog objects, grants, MCP registration, and the Databricks agent app |
| `foundry/` | Foundry model connection to APIM, prompt agent, MCP tool connection |
| `scripts/` | Sign-in and tenant checks |
| `tests/` | `feasibility/` checks each auth hop on its own; `e2e/` checks the three flows |

## Prerequisites

Azure subscription (Contributor + User Access Administrator), a Databricks account with a Unity Catalog metastore
in the target region, `az`, `terraform`, `databricks` CLI, and `uv`.

## Run

```bash
cp infra/sandbox.tfvars.example infra/sandbox.tfvars   # fill in IDs
az login --tenant <tenant-id>
make whoami            # every credential must show your tenant
make up                # ~15 min: Azure, Entra, APIM, Foundry, Databricks + catalog on its own storage
make databricks        # per-user OAuth connection + MCP service for the APIM Graph MCP
make foundry           # Foundry prompt agent on a Databricks model via APIM
make login             # sign in once as the demo user and consent
make test-feasibility  # each auth hop on its own
make test              # the three flows end to end
make down
```

## The 3 flows to test

| # | Sign in to | Do this | Identity at each hop |
|---|---|---|---|
| **1** | **Databricks** | Open the agent app in the workspace (Compute → Apps → `uga-agent`) and ask *"Who am I in Microsoft 365?"* On first use, sign in once to the `graph` connection. | You → Databricks app (**you**) → Unity Gateway MCP (**you**, your own OAuth token) → APIM → OBO → Microsoft Graph (**you**) |
| **2** | **Foundry** | Open the Foundry project → Agents → `uga-databricks-agent` → Playground and send any prompt. | You → Foundry agent → APIM → Databricks model `databricks-claude-sonnet-5` (**Foundry project managed identity**: a Databricks service principal; without the workspace-access entitlement Databricks returns 403, and its usage is attributed to that principal) |
| **3** | **CLI** (`make test`) | `tests/e2e/test_flows.py::test_flow3_*` sends `SELECT current_user()` to the Databricks SQL MCP through APIM with your gateway token. *(A Foundry agent using an OAuth passthrough MCP tool is next.)* | You → APIM → OBO → Databricks managed MCP `system.ai.dbsql` (**you**: your Unity Catalog grants apply) |

Flow #2 is the only hop where an identity other than the user's runs the request. That's by design: model capacity is
governed and tracked per Foundry project, and data and tools always run as the user.

To see who APIM saw at each hop (claims only, never tokens), query Application Insights:
`traces | where message startswith "identity-hop"`.
