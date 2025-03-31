variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}

variable "target_cluster_server" {
  description = "The target Kubernetes API server for ArgoCD Application destination"
  type        = string
}
