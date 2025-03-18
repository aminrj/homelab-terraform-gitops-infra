resource "helm_release" "longhorn" {
  name       = "longhorn"
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  namespace  = "longhorn-system"

  create_namespace = true

  values = [file("${path.module}/values.yaml")]

  wait = false

}
