terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}

# Install cert-manager using Helm (CRDs from the chart, kept if the release is ever removed)
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  chart            = "cert-manager"
  repository       = "https://charts.jetstack.io"
  version          = var.chart_version
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    crds = { enabled = true, keep = true }
    # Public resolvers for the DNS-01 self-check: the lab's split DNS would answer for lab.aminrj.com.
    dns01RecursiveNameserversOnly = true
    dns01RecursiveNameservers     = "1.1.1.1:53,9.9.9.9:53"
  })]
}

# Wait for cert-manager CRDs to be available
resource "time_sleep" "wait_for_cert_manager_crds" {
  depends_on      = [helm_release.cert_manager]
  create_duration = "60s"
}

# Cloudflare token for DNS-01 (Key Vault gitops-cloudflare-api-token, loaded by the Makefile).
# Without it the issuers exist but certificates stay pending.
resource "kubernetes_secret" "cloudflare_api_token" {
  count = var.cloudflare_api_token == "" ? 0 : 1
  metadata {
    name      = "cloudflare-api-token"
    namespace = "cert-manager"
  }
  data       = { "api-token" = var.cloudflare_api_token }
  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "issuer" {
  for_each = {
    letsencrypt-staging = "https://acme-staging-v02.api.letsencrypt.org/directory"
    letsencrypt-prod    = "https://acme-v02.api.letsencrypt.org/directory"
  }
  depends_on        = [time_sleep.wait_for_cert_manager_crds]
  server_side_apply = true
  yaml_body = templatefile("${path.module}/issuers/letsencrypt.yaml.tpl", {
    name = each.key, server = each.value, email = var.acme_email, zone = var.dns_zone
  })
}

moved {
  from = kubectl_manifest.letsencrypt_staging
  to   = kubectl_manifest.issuer["letsencrypt-staging"]
}

moved {
  from = kubectl_manifest.letsencrypt_prod
  to   = kubectl_manifest.issuer["letsencrypt-prod"]
}
