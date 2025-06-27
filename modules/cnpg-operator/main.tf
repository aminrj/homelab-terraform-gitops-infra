terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
  }
}

resource "helm_release" "cnpg_operator" {
  name             = "cloudnative-pg"
  namespace        = var.namespace
  # namespace        = "cnpg" #TODO change this
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = "0.24.0"
  create_namespace = true
  wait             = true

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      enable_crds        = true
    })
  ]
}


