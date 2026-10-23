resource "azurerm_api_management" "this" {
  name                = "${local.name}-apim"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  publisher_name      = "unity-gateway-apim"
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_api_management_logger" "appi" {
  name                = "appi"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  resource_id         = azurerm_application_insights.this.id

  application_insights {
    connection_string = azurerm_application_insights.this.connection_string
  }
}

resource "azurerm_api_management_diagnostic" "appi" {
  identifier               = "applicationinsights"
  api_management_name      = azurerm_api_management.this.name
  resource_group_name      = azurerm_resource_group.this.name
  api_management_logger_id = azurerm_api_management_logger.appi.id
  sampling_percentage      = 100
  always_log_errors        = true
  verbosity                = "information"
}

# --- Named values referenced by the policy XML in ../apim/policies.

locals {
  named_values = {
    "tenant-id"         = var.tenant_id
    "gateway-app-id"    = azuread_application.gateway.client_id
    "gateway-uri"       = local.gateway_uri
    "databricks-host"   = local.workspace_host
    "databricks-app-id" = local.databricks_app_id
    "foundry-mi-app-id" = data.azuread_service_principal.foundry_project.client_id
    "apim-gateway-url"  = azurerm_api_management.this.gateway_url
  }
}

resource "azurerm_api_management_named_value" "this" {
  for_each            = local.named_values
  name                = each.key
  display_name        = each.key
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  value               = each.value
}

# --- Reusable policy fragments (validate the caller, exchange tokens, log claims).

locals {
  fragments = ["validate-user", "validate-foundry-mi", "obo-exchange", "log-claims"]
}

resource "azurerm_api_management_policy_fragment" "this" {
  for_each          = toset(local.fragments)
  api_management_id = azurerm_api_management.this.id
  name              = each.key
  format            = "rawxml"
  value             = file("${path.module}/../apim/policies/fragments/${each.key}.xml")

  depends_on = [azurerm_api_management_named_value.this]
}

# --- Probe API: feasibility checks for each auth hop (returns claims, never tokens).

resource "azurerm_api_management_api" "probe" {
  name                  = "probe"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = azurerm_resource_group.this.name
  revision              = "1"
  display_name          = "Probe"
  path                  = "probe"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://${local.workspace_host}"
}

resource "azurerm_api_management_api_operation" "probe" {
  for_each            = toset(["whoami", "obo-databricks", "obo-graph"])
  operation_id        = each.key
  api_name            = azurerm_api_management_api.probe.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  display_name        = each.key
  method              = "GET"
  url_template        = "/${each.key}"
}

resource "azurerm_api_management_api_operation_policy" "probe" {
  for_each            = azurerm_api_management_api_operation.probe
  api_name            = azurerm_api_management_api.probe.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  operation_id        = each.value.operation_id
  xml_content         = file("${path.module}/../apim/policies/probe-${each.key}.xml")

  depends_on = [azurerm_api_management_policy_fragment.this]
}

# --- Flow #2: Foundry agent -> Databricks Foundation Models (OpenAI chat completions).

resource "azurerm_api_management_api" "databricks_models" {
  name                  = "databricks-models"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = azurerm_resource_group.this.name
  revision              = "1"
  display_name          = "Databricks Foundation Models"
  path                  = "databricks/models"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://${local.workspace_host}/serving-endpoints"
}

resource "azurerm_api_management_api_operation" "chat_completions" {
  operation_id        = "chat-completions"
  api_name            = azurerm_api_management_api.databricks_models.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  display_name        = "Chat completions"
  method              = "POST"
  url_template        = "/chat/completions"
}

resource "azurerm_api_management_api_policy" "databricks_models" {
  api_name            = azurerm_api_management_api.databricks_models.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content         = file("${path.module}/../apim/policies/databricks-models.xml")

  depends_on = [azurerm_api_management_policy_fragment.this]
}

# --- Flow #3: user -> APIM (OBO) -> Databricks managed MCP (streamable HTTP passthrough).

resource "azurerm_api_management_api" "databricks_mcp" {
  name                  = "databricks-mcp"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = azurerm_resource_group.this.name
  revision              = "1"
  display_name          = "Databricks managed MCP"
  path                  = "databricks/mcp"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://${local.workspace_host}"
}

resource "azurerm_api_management_api_operation" "databricks_mcp" {
  for_each            = toset(["GET", "POST", "DELETE"])
  operation_id        = "mcp-${lower(each.key)}"
  api_name            = azurerm_api_management_api.databricks_mcp.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  display_name        = "MCP ${each.key}"
  method              = each.key
  url_template        = "/*"
}

resource "azurerm_api_management_api_policy" "databricks_mcp" {
  api_name            = azurerm_api_management_api.databricks_mcp.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content         = file("${path.module}/../apim/policies/databricks-mcp.xml")

  depends_on = [azurerm_api_management_policy_fragment.this]
}
