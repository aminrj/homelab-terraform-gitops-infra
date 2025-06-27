# modules/microceph/variables.tf

variable "prometheus_release_name" {
  description = "Name of the Prometheus release for label matching"
  type        = string
  default     = "kube-promethues-stack"
}

variable "deploy_microceph_tools" {
  description = "Whether to deploy MicroCeph management tools"
  type        = bool
  default     = false
}

variable "enable_status_checks" {
  description = "Whether to enable periodic MicroCeph status checks"
  type        = bool
  default     = false
}

variable "monitoring_namespace" {
  description = "Namespace where Prometheus/Grafana is deployed"
  type        = string
  default     = "monitoring"
}

variable "microceph_manager_ip" {
  description = "IP address of the active MicroCeph manager node"
  type        = string
  default     = "10.0.30.15"
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}
