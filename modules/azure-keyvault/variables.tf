variable "app_name" {
  description = "Azure AD application name"
  type        = string
}

variable "key_vault_name" {
  description = "Azure Key Vault name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Azure Resource Group"
  type        = string
}

variable "storage_account_name" {
  type        = string
  description = "Name of the storage account"
}

# variable "subscription_id" {
#   type        = string
#   description = "subscription id"
# }
