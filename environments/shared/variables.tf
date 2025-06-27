
variable "kubeconfig" {
  type        = string
  description = "Path to kubeconfig file"
}

variable "kube_context" {
  type        = string
  description = "Kubernetes context to use"
}

variable "kubelet_root_dir" {
  type        = string
  description = "Kubelet root dir for Longhorn"
}

variable "target_cluster_server" {
  type        = string
  description = "Target cluster server address for ArgoCD"
}

variable "namespace" {
  type        = string
  description = "Namespace to deploy CNPG operator"
  default     = "cnpg"
}

variable "metallb_address_range" {
  type        = string
  description = "Address range for MetalLB IP Pool"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for external-dns"
  type        = string
  sensitive   = true
}

variable "storage_class" {
  description = "Storage class to use for qa cluster"
  type        = string
}

variable "pg_storage_class" {
  description = "Storage class for PostgreSQL/CNPG"
  type        = string
  default     = "cnpg-longhorn"
}


variable "ui_service_type" {
  type    = string
  default = "LoadBalancer"
}

variable "slack_webhook_url" {
  description = "Slack Webhook url for alert manager"
  type        = string
}
