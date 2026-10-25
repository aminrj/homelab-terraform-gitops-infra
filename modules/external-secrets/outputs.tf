output "namespace" {
  description = "Namespace of the External Secrets release (exists once the chart is installed)"
  value       = helm_release.external_secrets.namespace
}
