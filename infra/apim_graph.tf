# Flow #1: Microsoft Graph exposed as an MCP server in APIM.
#
#   graph REST API  - three Graph operations; the policy validates the user token and exchanges it (OBO) for Graph.
#   graph MCP API   - an MCP server (type "mcp") whose tools are those operations: https://<apim>/graph-mcp/mcp
#
# Databricks registers the MCP server as a Unity Catalog MCP service; each user signs in once (per-user OAuth),
# so every tool call reaches Graph as that user.

resource "azurerm_api_management_api" "graph" {
  name                  = "graph"
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = azurerm_resource_group.this.name
  revision              = "1"
  display_name          = "Microsoft Graph (as the user)"
  path                  = "graph"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://graph.microsoft.com/v1.0"
}

locals {
  graph_operations = {
    get_my_profile = {
      url         = "/me"
      description = "Get the signed-in user's Microsoft 365 profile (id, name, email, job title)."
    }
    list_my_groups = {
      url         = "/me/memberOf"
      description = "List the groups and directory roles the signed-in user is a member of."
    }
    find_user = {
      url         = "/users/search/{name}"
      description = "Find people in the directory whose display name starts with the given name."
    }
  }
}

resource "azurerm_api_management_api_operation" "graph" {
  for_each            = local.graph_operations
  operation_id        = each.key
  api_name            = azurerm_api_management_api.graph.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  display_name        = each.key
  description         = each.value.description
  method              = "GET"
  url_template        = each.value.url

  dynamic "template_parameter" {
    for_each = each.key == "find_user" ? ["name"] : []
    content {
      name        = template_parameter.value
      type        = "string"
      required    = true
      description = "Start of the person's display name."
    }
  }
}

resource "azurerm_api_management_api_policy" "graph" {
  api_name            = azurerm_api_management_api.graph.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content         = file("${path.module}/../apim/policies/graph.xml")

  depends_on = [azurerm_api_management_policy_fragment.this]
}

resource "azapi_resource" "graph_mcp" {
  type      = "Microsoft.ApiManagement/service/apis@2025-09-01-preview"
  name      = "graph-mcp"
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      type                 = "mcp"
      displayName          = "Microsoft Graph MCP (as the user)"
      path                 = "graph-mcp"
      protocols            = ["https"]
      subscriptionRequired = false
    }
  }

  schema_validation_enabled = false
}

resource "azapi_resource" "graph_mcp_tool" {
  for_each  = azurerm_api_management_api_operation.graph
  type      = "Microsoft.ApiManagement/service/apis/tools@2025-09-01-preview"
  name      = each.key
  parent_id = azapi_resource.graph_mcp.id

  body = {
    properties = {
      displayName = each.key
      description = local.graph_operations[each.key].description
      # Reference the operation without the ";rev=1" suffix that azurerm puts in API IDs.
      operationId = "${azurerm_api_management.this.id}/apis/${azurerm_api_management_api.graph.name}/operations/${each.value.operation_id}"
    }
  }

  schema_validation_enabled = false
}

# azurerm (not azapi) so APIM's XML reformatting doesn't show up as drift; works for MCP-type APIs too.
resource "azurerm_api_management_api_policy" "graph_mcp" {
  api_name            = azapi_resource.graph_mcp.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content         = file("${path.module}/../apim/policies/graph-mcp.xml")

  depends_on = [azurerm_api_management_policy_fragment.this]
}
