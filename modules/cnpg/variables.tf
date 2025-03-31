variable "kubeconfig" {
  description = "Path to kubeconfig"
  type        = string
}

variable "release_name" {
  default     = "cloudnativepg"
  description = "Helm release name"
}

variable "namespace" {
  default     = "cnpg"
  description = "Namespace for CNPG"
}

variable "chart_version" {
  default     = "0.20.0"
  description = "CloudNativePG Helm chart version"
}

variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}
