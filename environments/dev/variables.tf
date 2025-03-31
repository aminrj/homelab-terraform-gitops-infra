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

variable "kube_context" {
  type        = string
  description = "The kube context name to use"
}

variable "target_cluster_server" {
  description = "The target Kubernetes API server for ArgoCD Application destination"
  type        = string
}

