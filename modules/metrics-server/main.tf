resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2" # check latest version at https://artifacthub.io/packages/helm/metrics-server/metrics-server

  values = [ file("${path.module}/values.yaml") ]

  wait    = false
}
