data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  name = "${var.prefix}-${random_string.suffix.result}"
  tags = merge({ project = "unity-gateway-apim", managed_by = "terraform" }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = local.tags
}

# --- Monitoring: APIM traces carry token claims (never tokens) for identity assertions.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${local.name}-law"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${local.name}-appi"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}
