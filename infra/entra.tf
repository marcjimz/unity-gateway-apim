# Two app registrations:
#   gateway  - the API that APIM protects (audience api://<prefix>-gateway-<suffix>). It is also the
#              OBO middle tier: APIM exchanges the user's gateway token for Databricks / Graph tokens,
#              authenticating with its own managed identity as a federated credential (no secret).
#   client   - the confidential client that users sign in through: Databricks UC connection (flow #1),
#              Foundry MCP tool connection (flow #3), and the local test CLI.

locals {
  databricks_app_id = "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" # Azure Databricks first-party app
  graph_app_id      = "00000003-0000-0000-c000-000000000000"
  gateway_uri       = "api://${azuread_application.gateway.client_id}"
  workspace_host    = azurerm_databricks_workspace.this.workspace_url
}

# Owners must be set explicitly: the provider removes the creator otherwise, and a guest
# (or any user without an Entra role) can then no longer manage the app.
data "azuread_client_config" "current" {}

data "azuread_service_principal" "databricks" {
  client_id = local.databricks_app_id
}

data "azuread_service_principal" "graph" {
  client_id = local.graph_app_id
}

resource "random_uuid" "scope_mcp" {}
resource "random_uuid" "scope_models" {}

resource "azuread_application" "gateway" {
  display_name     = "${local.name}-gateway"
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = random_uuid.scope_mcp.result
      value                      = "mcp.invoke"
      type                       = "User"
      admin_consent_display_name = "Invoke MCP tools as the signed-in user"
      admin_consent_description  = "Call MCP servers behind APIM on behalf of the signed-in user."
      user_consent_display_name  = "Invoke MCP tools as you"
      user_consent_description   = "Call MCP servers behind APIM on your behalf."
    }

    oauth2_permission_scope {
      id                         = random_uuid.scope_models.result
      value                      = "models.invoke"
      type                       = "User"
      admin_consent_display_name = "Invoke models as the signed-in user"
      admin_consent_description  = "Call models behind APIM on behalf of the signed-in user."
      user_consent_display_name  = "Invoke models as you"
      user_consent_description   = "Call models behind APIM on your behalf."
    }
  }

  # Downstream delegated permissions used by APIM's OBO exchange.
  required_resource_access {
    resource_app_id = local.databricks_app_id
    resource_access {
      id   = data.azuread_service_principal.databricks.oauth2_permission_scope_ids["user_impersonation"]
      type = "Scope"
    }
  }

  required_resource_access {
    resource_app_id = local.graph_app_id
    resource_access {
      id   = data.azuread_service_principal.graph.oauth2_permission_scope_ids["User.Read"]
      type = "Scope"
    }
    resource_access {
      id   = data.azuread_service_principal.graph.oauth2_permission_scope_ids["User.ReadBasic.All"]
      type = "Scope"
    }
  }

  # Used once, by `make login`, so the user consents to the gateway's downstream permissions.
  # Bundled consent through knownClientApplications is skipped when the client is pre-authorized.
  public_client {
    redirect_uris = ["http://localhost"]
  }

  lifecycle {
    # Managed by the azuread_application_* resources below.
    ignore_changes = [api[0].known_client_applications, identifier_uris]
  }
}

resource "azuread_application_identifier_uri" "gateway" {
  application_id = azuread_application.gateway.id
  identifier_uri = local.gateway_uri
}

resource "azuread_service_principal" "gateway" {
  client_id = azuread_application.gateway.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# APIM's managed identity authenticates the gateway app during OBO (client_assertion), so no secret lives in APIM.
resource "azuread_application_federated_identity_credential" "gateway_apim_mi" {
  application_id = azuread_application.gateway.id
  display_name   = "apim-managed-identity"
  issuer         = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
  subject        = azurerm_api_management.this.identity[0].principal_id
  audiences      = ["api://AzureADTokenExchange"]
}

resource "azuread_application" "client" {
  display_name     = "${local.name}-client"
  owners           = [data.azuread_client_config.current.object_id]
  sign_in_audience = "AzureADMyOrg"

  required_resource_access {
    resource_app_id = azuread_application.gateway.client_id
    resource_access {
      id   = random_uuid.scope_mcp.result
      type = "Scope"
    }
    resource_access {
      id   = random_uuid.scope_models.result
      type = "Scope"
    }
  }

  web {
    # Databricks UC HTTP connection (OAuth U2M per user). Foundry's generated redirect URL is
    # appended after the Foundry MCP connection exists (see foundry/README).
    redirect_uris = ["https://${local.workspace_host}/login/oauth/http.html"]
  }

  public_client {
    # Local test CLI (MSAL interactive / device code).
    redirect_uris = ["http://localhost"]
  }

  fallback_public_client_enabled = true

  lifecycle {
    ignore_changes = [web[0].redirect_uris]
  }
}

resource "azuread_service_principal" "client" {
  client_id = azuread_application.client.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "client" {
  application_id = azuread_application.client.id
  display_name   = "uc-connection-and-foundry"
  end_date       = timeadd(timestamp(), "2160h")

  lifecycle {
    ignore_changes = [end_date]
  }
}

# Combined consent: signing in through the client also consents the gateway's downstream
# (Databricks, Graph) permissions, so OBO works without a separate consent step.
resource "azuread_application_known_clients" "gateway" {
  application_id   = azuread_application.gateway.id
  known_client_ids = [azuread_application.client.client_id]
}

# The client is pre-authorized for the gateway scopes, so users are not prompted for them.
resource "azuread_application_pre_authorized" "client" {
  application_id       = azuread_application.gateway.id
  authorized_client_id = azuread_application.client.client_id
  permission_ids       = [random_uuid.scope_mcp.result, random_uuid.scope_models.result]
}

# Optional tenant-wide consent (requires an Entra admin running Terraform).
resource "azuread_service_principal_delegated_permission_grant" "gateway_databricks" {
  count                                = var.grant_admin_consent ? 1 : 0
  service_principal_object_id          = azuread_service_principal.gateway.object_id
  resource_service_principal_object_id = data.azuread_service_principal.databricks.object_id
  claim_values                         = ["user_impersonation"]
}

resource "azuread_service_principal_delegated_permission_grant" "gateway_graph" {
  count                                = var.grant_admin_consent ? 1 : 0
  service_principal_object_id          = azuread_service_principal.gateway.object_id
  resource_service_principal_object_id = data.azuread_service_principal.graph.object_id
  claim_values                         = ["User.Read", "User.ReadBasic.All"]
}
