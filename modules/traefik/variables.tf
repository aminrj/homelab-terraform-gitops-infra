variable "chart_version" {
  description = "Traefik Helm chart version (docs/versions.md in homelab-foundation)"
  type        = string
  default     = "42.1.3" # Traefik v3.7.16, 2026-10
}

variable "load_balancer_ip" {
  description = "MetalLB address for the ingress (homelab-foundation: kubernetes.ingress_vip)"
  type        = string
}
