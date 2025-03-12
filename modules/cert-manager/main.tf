resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.0"
  namespace  = "cert-manager"
  create_namespace = true

  wait       = false
  set {
      name  = "installCRDs"
      value = "true"
    }
}
