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

# Install cert-manager using Helm
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  chart            = "cert-manager"
  repository       = "https://charts.jetstack.io"
  version          = "v1.13.2"
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# Wait for cert-manager CRDs to be available
resource "time_sleep" "wait_for_cert_manager_crds" {
  depends_on = [helm_release.cert_manager]
  create_duration = "60s"
}

# Use kubectl provider for CRD-dependent resources
resource "kubectl_manifest" "letsencrypt_staging" {
  depends_on = [time_sleep.wait_for_cert_manager_crds]
  
  validate_schema    = false
  server_side_apply  = true
  wait_for_rollout   = true
  
  yaml_body = file("${path.module}/issuers/letsencrypt-staging.yaml")
}

resource "kubectl_manifest" "letsencrypt_prod" {
  depends_on = [time_sleep.wait_for_cert_manager_crds]
  
  validate_schema    = false
  server_side_apply  = true
  wait_for_rollout   = true
  
  yaml_body = file("${path.module}/issuers/letsencrypt-prod.yaml")
}

