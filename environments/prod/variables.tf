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

# Cnpg Operator variables
variable "use_longhorn_storage" {
  description = "Use longhorn as storage for prod?"
  type        = bool
  default     = true
}

# CNPG cluster variables

variable "pg_cluster_name" {
  description = "Postgres cluster name"
  type        = string
  default     = "pg-prod"
}

variable "pg_instance_count" {
  description = "Number of postgres instances"
  type        = number
  default     = 2
}

variable "storage_class" {
  description = "Storage class to use for prod cluster"
  type        = string
  default     = "longhorn"
}

variable "pg_storage_class" {
  description = "Storage class to use for prod cluster"
  type        = string
  default     = "cnpg-longhorn"
}

variable "pg_storage_size" {
  description = "Postgres data size"
  type        = string
  default     = "20Gi"
}

variable "pg_superuser_secret" {
  description = "Secret name for postgres superuser"
  type        = string
  default     = "pg-superuser-prod"
}

variable "pg_app_secret" {
  description = "Secret name for postgres app user"
  type        = string
  default     = "pg-app-prod"
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
