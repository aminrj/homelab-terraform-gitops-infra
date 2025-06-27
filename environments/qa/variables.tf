variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "helm_timeout" {
  description = "Timeout for Helm releases"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for Helm resources to be ready"
  type        = bool
  default     = false
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for external-dns"
  type        = string
  sensitive   = true
}

variable "kubeconfig" {
  type        = string
  description = "Path to kubeconfig file"
}

variable "kube_context" {
  type        = string
  description = "The kube context name to use"
}


# CNPG cluster variables

variable "pg_cluster_name" {
  description = "Postgres cluster name"
  type        = string
  default     = "pg-qa"
}

variable "pg_instance_count" {
  description = "Number of postgres instances"
  type        = number
  default     = 2
}

variable "storage_class" {
  description = "Storage class to use for qa cluster"
  type        = string
}

variable "pg_storage_class" {
  description = "Storage class to use for qa cluster"
  type        = string
}

variable "pg_storage_size" {
  description = "Postgres data size"
  type        = string
  default     = "20Gi"
}

variable "pg_superuser_secret" {
  description = "Secret name for postgres superuser"
  type        = string
  default     = "pg-superuser-qa"
}

variable "pg_app_secret" {
  description = "Secret name for postgres app user"
  type        = string
  default     = "pg-app-qa"
}

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

variable "subscription_id" {
  type        = string
  description = "subscription id"
}
