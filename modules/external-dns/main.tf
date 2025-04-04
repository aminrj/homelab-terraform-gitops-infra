resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
  }
}

resource "helm_release" "external-dns" {
  name       = "external-dns"
  chart      = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  version    = "1.15.2"
  namespace = kubernetes_namespace.external_dns.metadata[0].name
  create_namespace = false


  depends_on = [kubernetes_secret.cloudflare_api_token]

  values = [file("${path.module}/values.yaml")]
  
  wait       = false

}

resource "kubernetes_secret" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-key"
    namespace = kubernetes_namespace.external_dns.metadata[0].name
  }

  data = {
    apiKey = var.cloudflare_api_token
  }

  type = "Opaque"
}

