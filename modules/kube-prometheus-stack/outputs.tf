output "prometheus_url" {
  description = "Prometheus UI URL"
  value       = "http://kube-prometheus-stack-prometheus.${var.namespace}.svc.cluster.local:9090"
}

output "grafana_url" {
  description = "Grafana UI URL"
  value       = "http://kube-prometheus-stack-grafana.${var.namespace}.svc.cluster.local:80"
}

