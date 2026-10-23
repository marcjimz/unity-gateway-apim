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
make login             # sign in once as the demo user and consent
make test-feasibility  # each auth hop on its own
make test              # the three flows end to end
make down
```

## The 3 flows to test

| # | Sign in to | Do this | Identity at each hop |
|---|---|---|---|
| **1** | **Databricks** | Open the agent app in the workspace (Compute → Apps → `uga-agent`) and ask *"Who am I in Microsoft 365?"* On first use, sign in once to the `graph` connection. | You → Databricks app (**you**) → Unity Gateway MCP (**you**, your own OAuth token) → APIM → OBO → Microsoft Graph (**you**) |
| **2** | **Foundry** | Open the Foundry project → Agents → `uga-databricks-agent` → Playground and send any prompt. | You → Foundry agent → APIM → Databricks model endpoint (**Foundry project managed identity**: a Databricks service principal with `CAN_QUERY`; usage shows up in Databricks system tables) |
| **3** | **Foundry** | In the same project, open `uga-data-agent` and ask *"Run SELECT current_user()"*. On first use, approve the consent link. | You → Foundry MCP tool (**you**, OAuth passthrough) → APIM → OBO → Databricks managed MCP `system.ai.dbsql` (**you**: your Unity Catalog grants and row filters apply) |

Flow #2 is the only hop where an identity other than the user's runs the request. That's by design: model capacity is
governed and tracked per Foundry project, and data and tools always run as the user.

To see who APIM saw at each hop (claims only, never tokens), query Application Insights:
`traces | where message startswith "identity-hop"`.
