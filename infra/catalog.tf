# Unity Catalog catalog on our own storage (not Databricks Default Storage, not the shared metastore root).
#
#   ADLS Gen2 account + container  <- Access Connector (managed identity, Storage Blob Data Contributor)
#   storage credential -> external location -> catalog uga_<suffix> (MANAGED LOCATION) -> schema tools
#
# The catalog holds the HTTP connection and MCP service for flow #1 (see ../databricks/setup.py).

provider "databricks" {
  alias                       = "workspace"
  host                        = "https://${azurerm_databricks_workspace.this.workspace_url}"
  azure_workspace_resource_id = azurerm_databricks_workspace.this.id
  azure_tenant_id             = var.tenant_id
  auth_type                   = "azure-cli"
}

locals {
  catalog = "${var.prefix}_${random_string.suffix.result}"
}

resource "azurerm_storage_account" "uc" {
  name                            = "${var.prefix}${random_string.suffix.result}uc"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "uc" {
  name               = "unity-catalog"
  storage_account_id = azurerm_storage_account.uc.id
}

resource "azurerm_databricks_access_connector" "uc" {
  name                = "${local.name}-uc-connector"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "uc_connector_storage" {
  scope                = azurerm_storage_account.uc.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.uc.identity[0].principal_id
}

resource "databricks_storage_credential" "uc" {
  provider = databricks.workspace
  name     = "${local.catalog}_cred"
  comment  = "unity-gateway-apim: access connector for ${azurerm_storage_account.uc.name}"

  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.uc.id
  }

  depends_on = [databricks_metastore_assignment.this]
}

resource "databricks_external_location" "uc" {
  provider        = databricks.workspace
  name            = "${local.catalog}_location"
  url             = "abfss://${azurerm_storage_container.uc.name}@${azurerm_storage_account.uc.name}.dfs.core.windows.net/"
  credential_name = databricks_storage_credential.uc.name
  comment         = "unity-gateway-apim managed storage"

  # Role assignments take a few minutes to propagate; the catalog below exercises access anyway.
  skip_validation = true
  depends_on      = [azurerm_role_assignment.uc_connector_storage]
}

resource "databricks_catalog" "this" {
  provider     = databricks.workspace
  name         = local.catalog
  storage_root = "${databricks_external_location.uc.url}${local.catalog}"
  comment      = "unity-gateway-apim demo"
}

resource "databricks_schema" "tools" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this.name
  name         = "tools"
  comment      = "HTTP connections and MCP services"
}
