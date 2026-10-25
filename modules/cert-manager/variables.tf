variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}

variable "chart_version" {
  description = "cert-manager chart version (supports the cluster's Kubernetes release)"
  type        = string
  default     = "v1.21.3" # 2026-10, Kubernetes 1.33-1.36
}

variable "cloudflare_api_token" {
  description = "Cloudflare token with Zone:DNS:Edit on dns_zone; empty = no certificates yet"
  type        = string
  sensitive   = true
  default     = ""
}

variable "acme_email" {
  type    = string
  default = "contact@molntek.com"
}

variable "dns_zone" {
  type    = string
  default = "aminrj.com"
}
