variable "cloudflare_api_token" {
  description = "Cloudflare API token for external-dns"
  type        = string
  sensitive   = true
}

variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}
