output "argocd_bcrypt" {
  value     = random_password.this["argocd"].bcrypt_hash
  sensitive = true
}

output "argocd_mtime" {
  value = time_static.argocd_password.rfc3339
}

output "grafana_password" {
  value     = random_password.this["grafana"].result
  sensitive = true
}
