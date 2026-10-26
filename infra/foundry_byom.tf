# Flow #2: Foundry agent -> APIM -> Databricks Foundation Model APIs ("bring your own model").
#
# The Foundry project's managed identity is the actor. Foundry requests a token for Azure Databricks
# (audience below), APIM accepts only that identity (validate-foundry-mi.xml) and forwards the token,
# and Databricks sees the identity as its own service principal, so usage is attributed to the project.
# Agents reference a model as "<connection name>/<model name>", e.g. "databricks-models/databricks-claude-sonnet-5".

variable "foundry_models" {
  description = "Databricks pay-per-token chat endpoints to expose to Foundry agents through APIM."
  type        = list(string)
  default     = ["databricks-claude-sonnet-5", "databricks-gpt-oss-120b"]
}

resource "azapi_resource" "foundry_databricks_models" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "databricks-models"
  parent_id = azurerm_cognitive_account_project.this.id

  body = {
    properties = {
      category      = "ApiManagement"
      target        = "${azurerm_api_management.this.gateway_url}/${azurerm_api_management_api.databricks_models.path}"
      authType      = "ProjectManagedIdentity"
      audience      = local.databricks_app_id
      isSharedToAll = false
      credentials   = {}
      metadata = {
        deploymentInPath = "false"
        models = jsonencode([
          for m in var.foundry_models : {
            name       = m
            properties = { model = { name = m, version = "1", format = "OpenAI" } }
          }
        ])
      }
    }
  }

  schema_validation_enabled = false
}

# The Foundry project identity as a Databricks service principal. Pay-per-token endpoints have no
# per-endpoint grants; the gate is the workspace-access entitlement (without it Databricks returns 403).
# Its calls are attributed to this service principal in Databricks audit and usage tables.
resource "databricks_service_principal" "foundry_project" {
  provider         = databricks.workspace
  application_id   = data.azuread_service_principal.foundry_project.client_id
  display_name     = data.azuread_service_principal.foundry_project.display_name # Databricks syncs the Entra name
  active           = true
  workspace_access = true

  depends_on = [databricks_metastore_assignment.this]
}

output "foundry_connection" {
  value = azapi_resource.foundry_databricks_models.name
}

output "foundry_models" {
  value = var.foundry_models
}
