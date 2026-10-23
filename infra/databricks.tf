resource "azurerm_databricks_workspace" "this" {
  name                        = "${local.name}-dbw"
  location                    = azurerm_resource_group.this.location
  resource_group_name         = azurerm_resource_group.this.name
  sku                         = "premium"
  managed_resource_group_name = "${local.name}-dbw-managed-rg"
  tags                        = local.tags
}

# Post-provisioning step: register the new workspace with the account's existing
# Unity Catalog metastore in this region.
resource "databricks_metastore_assignment" "this" {
  provider     = databricks.account
  workspace_id = azurerm_databricks_workspace.this.workspace_id
  metastore_id = var.metastore_id
}
