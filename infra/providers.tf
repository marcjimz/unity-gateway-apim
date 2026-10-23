terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.5"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.130"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State stays local by default so it survives the weekly sandbox wipe.
  # For shared use, switch to an azurerm backend in a subscription that is not wiped.
}

# Every provider is pinned to the tenant explicitly. The az CLI can otherwise
# hand out tokens for the user's home tenant instead of the sandbox tenant.
provider "azurerm" {
  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  storage_use_azuread = true # storage accounts have shared keys disabled
  features {
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "databricks" {
  alias           = "account"
  host            = "https://accounts.azuredatabricks.net"
  account_id      = var.databricks_account_id
  azure_tenant_id = var.tenant_id
  auth_type       = "azure-cli"
}
