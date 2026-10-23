output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "tenant_id" {
  value = var.tenant_id
}

output "databricks_host" {
  value = "https://${local.workspace_host}"
}

output "databricks_workspace_id" {
  value = azurerm_databricks_workspace.this.workspace_id
}

output "apim_gateway_url" {
  value = azurerm_api_management.this.gateway_url
}

output "apim_name" {
  value = azurerm_api_management.this.name
}

output "gateway_app_id" {
  value = azuread_application.gateway.client_id
}

output "gateway_scope" {
  value = "${local.gateway_uri}/mcp.invoke"
}

output "client_app_id" {
  value = azuread_application.client.client_id
}

output "client_app_object_id" {
  value = azuread_application.client.object_id
}

output "client_secret" {
  value     = azuread_application_password.client.value
  sensitive = true
}

output "foundry_account" {
  value = azurerm_cognitive_account.foundry.name
}

output "foundry_project_endpoint" {
  value = "https://${azurerm_cognitive_account.foundry.custom_subdomain_name}.services.ai.azure.com/api/projects/${azurerm_cognitive_account_project.this.name}"
}

output "foundry_project_id" {
  value = azurerm_cognitive_account_project.this.id
}

output "foundry_mi_app_id" {
  description = "Application (client) ID of the Foundry project managed identity: the Databricks service principal for flow #2."
  value       = data.azuread_service_principal.foundry_project.client_id
}

output "app_insights_app_id" {
  value = azurerm_application_insights.this.app_id
}

output "catalog" {
  value = databricks_catalog.this.name
}
