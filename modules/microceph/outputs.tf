# modules/microceph/outputs.tf

output "servicemonitor_name" {
  description = "Name of the MicroCeph ServiceMonitor"
  value       = "microceph-mgr"
}

output "prometheus_rule_name" {
  description = "Name of the MicroCeph PrometheusRule"
  value       = "microceph-storage-alerts"
}

output "microceph_service_name" {
  description = "Name of the MicroCeph manager service"
  value       = kubernetes_service.microceph_mgr.metadata[0].name
}

output "microceph_endpoints_name" {
  description = "Name of the MicroCeph manager endpoints"
  value       = kubernetes_endpoints.microceph_mgr.metadata[0].name
}
