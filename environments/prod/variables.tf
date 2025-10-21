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
}

variable "pg_storage_class" {
  description = "Storage class to use for prod cluster"
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

variable "subscription_id" {
  type        = string
  description = "subscription id"
}

variable "metallb_address_range" {
  type        = string
  description = "Address range for MetalLB load balancers"
  default     = ""
}

variable "kubelet_root_dir" {
  type        = string
  description = "Root directory for kubelet on nodes"
  default     = ""
}

variable "target_cluster_server" {
  type        = string
  description = "API server address for the in-cluster ArgoCD destination"
  default     = "https://kubernetes.default.svc"
}

variable "namespace" {
  type        = string
  description = "Default namespace used by shared modules"
  default     = "default"
}

variable "ui_service_type" {
  type        = string
  description = "Service type for UI components (LoadBalancer, ClusterIP, etc.)"
  default     = "LoadBalancer"
}

variable "slack_webhook_url" {
  type        = string
  description = "Slack webhook used by Alertmanager"
  default     = ""
}

variable "threat_intel_vt_api_key" {
  type        = string
  description = "VirusTotal API key for threat-intel workload"
  sensitive   = true
}

variable "threat_intel_shodan_api_key" {
  type        = string
  description = "Shodan API key for threat-intel workload"
  sensitive   = true
}

variable "threat_intel_abuseipdb_api_key" {
  type        = string
  description = "AbuseIPDB API key for threat-intel workload"
  sensitive   = true
}

variable "threat_intel_openai_api_key" {
  type        = string
  description = "OpenAI API key for threat-intel workload"
  sensitive   = true
}

variable "threat_intel_ollama_host" {
  type        = string
  description = "Ollama host endpoint consumed by threat-intel workload..."
}

variable "threat_intel_azure_container" {
  type        = string
  description = "Azure storage container identifier for threat-intel workload"
}
