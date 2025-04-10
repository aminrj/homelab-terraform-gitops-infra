variable "key_vault_id" {
  type        = string
  description = "The ID of the Azure Key Vault to store secrets in"
}

variable "app_name" {
  type        = string
  description = "Application prefix to prepend to secret names"
}

variable "static_secrets" {
  type        = map(string)
  default     = {}
  description = "Secrets with predefined values"
}

variable "random_secrets" {
  type        = list(string)
  default     = []
  description = "Secrets to auto-generate with random values"
}
