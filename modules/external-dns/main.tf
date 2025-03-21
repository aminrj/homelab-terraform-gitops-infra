resource "helm_release" "external-dns" {
  name       = "external-dns"
  chart      = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  version    = "1.15.2"
  namespace  = "external-dns"

  create_namespace = true

  wait       = false


  set {
    name  = "extraEnv[0].name"
    value = "CF_API_TOKEN"
  }

  set {
    name  = "extraEnv[0].valueFrom.secretKeyRef.name"
    value = "cloudflare-api-token-secret"
  }

  set {
    name  = "extraEnv[0].valueFrom.secretKeyRef.key"
    value = "CF_API_TOKEN"
  }

  set {
    name  = "provider"
    value = "cloudflare"
  }

  set {
    name  = "cloudflare.apiToken"
    value = var.cloudflare_api_token
  }
}

resource "kubernetes_secret" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token-secret"
    namespace = "external-dns"
  }

  data = {
    CF_API_TOKEN = var.cloudflare_api_token
  }

  type = "Opaque"
}
