
# Install Kube-promethues-stack
resource "helm_release" "kube-promethues-stack" {
  name       = "kube-promethues-stack"
  namespace  = "monitoring"
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  version    = "70.0.2"

  create_namespace = true

  values = [file("${path.module}/values.yaml")]
 
  wait    = false
}
