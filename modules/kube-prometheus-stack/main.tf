
# Install Kube-promethues-stack
resource "helm_release" "kube-promethues-stack" {
  name       = "kube-promethues-stack"
  namespace  = var.namespace
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  version    = var.helm_chart_version

  create_namespace = true
  wait = false

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      storage_class = var.storage_class
      slack_webhook_url = var.slack_webhook_url
    })
  ]
}
