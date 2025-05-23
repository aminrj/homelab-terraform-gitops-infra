variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}
