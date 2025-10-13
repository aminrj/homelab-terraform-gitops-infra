variable "namespace" {
  description = "Namespace where kube-prometheus-stack will be deployed"
  type        = string
  default     = "monitoring"
}

variable "helm_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "75.4.0"
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
variable "slack_webhook_url" {
  description = "Slack Webhook url for alert manager"
  type        = string
}

variable "priority_class_name" {
  description = "PriorityClass to assign to monitoring workloads"
  type        = string
  default     = "infra-critical"
}
