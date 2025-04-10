
variable "container_name" {
  type        = string
  description = "Name of the blob container"
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

