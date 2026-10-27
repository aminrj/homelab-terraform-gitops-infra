variable "namespace" {
  description = "Namespace where kube-prometheus-stack will be deployed"
  type        = string
  default     = "monitoring"
}

variable "helm_chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "92.3.0" # operator v0.94.1; from 75.4.0 on 2026-10-26
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

variable "grafana_admin_password" {
  description = "Grafana admin password (modules/admin-passwords)"
  type        = string
  sensitive   = true
}

variable "priority_class_name" {
  description = "PriorityClass to assign to monitoring workloads"
  type        = string
  default     = "infra-critical"
}

variable "ha_webhook_id" {
  description = "Home Assistant webhook id for alert notifications (Key Vault foundation-ha-alertmanager-webhook-id)"
  type        = string
  default     = ""
  sensitive   = true
}
