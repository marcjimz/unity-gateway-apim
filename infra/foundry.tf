resource "azurerm_cognitive_account" "foundry" {
  name                       = "${local.name}-foundry"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  kind                       = "AIServices"
  sku_name                   = "S0"
  custom_subdomain_name      = "${local.name}-foundry"
  project_management_enabled = true
  local_auth_enabled         = false
  tags                       = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# The project's managed identity is the actor for flow #2 (Foundry agent -> Databricks models).
# It is added to Databricks as a service principal and granted CAN_QUERY on the model endpoint.
resource "azurerm_cognitive_account_project" "this" {
  name                 = "${var.prefix}-project"
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  location             = azurerm_resource_group.this.location
  display_name         = "Unity Gateway APIM demo"
  tags                 = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# Users of flow #2 and #3 need to call agents in the project.
resource "azurerm_role_assignment" "foundry_user" {
  scope                = azurerm_cognitive_account.foundry.id
  role_definition_name = "Foundry User"
  principal_id         = data.azurerm_client_config.current.object_id
}

data "azuread_service_principal" "foundry_project" {
  object_id = azurerm_cognitive_account_project.this.identity[0].principal_id
}
