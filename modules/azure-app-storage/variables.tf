
variable "container_name" {
  type        = string
  description = "Name of the blob container"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the storage account"
}

variable "storage_account_name" {
  type        = string
  description = "Name of the Azure storage account"
}

variable "connection_string" {
  type        = string
  description = "Connection string to the Azure storage account"
}

variable "key_vault_id" {
  type        = string
  description = "Azure Key Vault ID to store the SAS token"
}
