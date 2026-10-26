
# Install Kube-promethues-stack
resource "helm_release" "kube-prometheus-stack" {
  name       = "kube-prometheus-stack"
  namespace  = var.namespace
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  version    = var.helm_chart_version

  create_namespace = true
  wait             = false

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      storage_class       = var.storage_class
      slack_webhook_url   = var.slack_webhook_url
      priority_class_name = var.priority_class_name
    })
  ]
}

# Grafana's admin login from Key Vault (modules/admin-passwords). Grafana reads it only when
# its database is new; for the existing one: `make grafana-admin-sync`.
resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = var.namespace
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = var.grafana_admin_password
  }
  depends_on = [helm_release.kube-prometheus-stack] # the release creates the namespace
}
