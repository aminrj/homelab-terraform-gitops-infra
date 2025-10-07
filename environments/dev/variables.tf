variable "metallb_address_range" {
  description = "Metallb address range"
  type        = string
}

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

variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}

variable "target_cluster_server" {
  description = "The target Kubernetes API server for ArgoCD Application destination"
  type        = string
}

variable "kube_context" {
  description = "Kubernetes context"
  type        = string
}

# CNPG cluster variables

variable "pg_cluster_name" {
  description = "Postgres cluster name"
  type        = string
  default     = "pg-dev"
}

variable "pg_instance_count" {
  description = "Number of postgres instances"
  type        = number
  default     = 1
}

variable "pg_storage_class" {
  description = "Storage class to use for dev cluster"
  type        = string
  default     = "local-path"
}

variable "pg_storage_size" {
  description = "Postgres data size"
  type        = string
  default     = "5Gi"
}

variable "pg_superuser_secret" {
  description = "Secret name for postgres superuser"
  type        = string
  default     = "pg-superuser-dev"
}

variable "pg_app_secret" {
  description = "Secret name for postgres app user"
  type        = string
  default     = "pg-app-dev"
}

variable "pg_monitoring_enabled" {
  description = "Enable monitoring (PodMonitor)"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class to use for workloads"
  type        = string
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

# variable "connection_string" {
#   type        = string
#   description = "Connection string to the Azure storage account"
# }


# variable "default_data_path" {
#   type = string
# }
#
# variable "default_replica_count" {
#   type    = number
#   default = 2
# }
#
# variable "kubelet_root_dir" {
#   type = string
# }
#
# variable "ui_service_type" {
#   type    = string
#   default = "LoadBalancer"
# }

variable "slack_webhook_url" {
  description = "Slack webhook URL for alertmanager notifications"
  type        = string
  default     = ""
}
