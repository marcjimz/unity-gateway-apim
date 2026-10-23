variable "subscription_id" {
  description = "Azure subscription to deploy into."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant that owns the subscription, the users, and the Databricks account."
  type        = string
}

variable "location" {
  description = "Azure region. Must have a Unity Catalog metastore in the Databricks account and support Model Serving."
  type        = string
  default     = "centralus"
}

variable "prefix" {
  description = "Short prefix for resource names (lowercase letters and digits)."
  type        = string
  default     = "uga"
}

variable "databricks_account_id" {
  description = "Azure Databricks account ID (accounts.azuredatabricks.net)."
  type        = string
}

variable "metastore_id" {
  description = "Existing Unity Catalog metastore in var.location to assign the new workspace to."
  type        = string
}

variable "apim_publisher_email" {
  description = "Publisher email required by API Management."
  type        = string
}

variable "apim_sku" {
  description = "API Management SKU. Foundry 'bring your own model' requires a v2 tier."
  type        = string
  default     = "StandardV2_1"
}

variable "grant_admin_consent" {
  description = "Pre-grant delegated permissions tenant-wide. Needs an Entra admin; leave false to rely on user consent at first sign-in."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
