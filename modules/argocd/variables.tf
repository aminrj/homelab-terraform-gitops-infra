variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}

variable "admin_password_bcrypt" {
  description = "bcrypt hash of the admin password (modules/admin-passwords)"
  type        = string
  sensitive   = true
}

variable "admin_password_mtime" {
  description = "When the admin password last changed (RFC 3339)"
  type        = string
}

variable "kube_context" {
  type = string
}

variable "target_cluster_server" {
  description = "The target Kubernetes API server for ArgoCD Application destination"
  type        = string
}
