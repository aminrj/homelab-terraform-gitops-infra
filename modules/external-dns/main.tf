resource "helm_release" "external-dns" {
  name       = "external-dns"
  chart      = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  version    = "1.15.2"
  namespace  = "external-dns"

  create_namespace = true

  depends_on = [kubernetes_secret.cloudflare_api_token]

  values = [file("${path.module}/values.yaml")]
  
  wait       = false

}

resource "kubernetes_secret" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-key"
    namespace = "external-dns"
  }

  data = {
    apiKey = var.cloudflare_api_token
  }

  type = "Opaque"
}

