output "namespace" {
  description = "Namespace of the ArgoCD release (exists once the chart is installed)"
  value       = helm_release.argocd.namespace
}
