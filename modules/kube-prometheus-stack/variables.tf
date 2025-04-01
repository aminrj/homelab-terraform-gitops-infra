variable "namespace" {
  description = "Namespace where kube-prometheus-stack will be deployed"
  type        = string
  default     = "monitoring"
}

variable "helm_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "70.4.1"
}

variable "values_yaml" {
  description = "Custom Helm values (YAML as string)"
  type        = string
  default     = ""
}

variable "kubeconfig" {
  type        = string
  description = "Path to the kubeconfig file"
}

variable "storage_class" {
  description = "The storage class to use for Prometheus, Grafana, and Alertmanager PVCs"
  type        = string
}
