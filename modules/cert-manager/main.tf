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


resource "kubernetes_manifest" "letsencrypt_staging" {
  manifest = yamldecode(file("${path.module}/issuers/letsencrypt-staging.yaml"))
}

resource "kubernetes_manifest" "letsencrypt_prod" {
  manifest = yamldecode(file("${path.module}/issuers/letsencrypt-prod.yaml"))
}
