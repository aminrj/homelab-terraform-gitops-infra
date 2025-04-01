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

resource "kubernetes_namespace" "cnpg" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_storage_class" "cnpg_longhorn" {
  count = var.use_longhorn_storage ? 1 : 0

  metadata {
    name = "cnpg-longhorn"
  }

  storage_provisioner = "driver.longhorn.io"

  parameters = {
    numberOfReplicas      = "1"
    staleReplicaTimeout   = "30"
  }

  reclaim_policy          = "Retain"
  volume_binding_mode     = "WaitForFirstConsumer"
  allow_volume_expansion  = true
}

resource "helm_release" "cnpg_operator" {
  name             = "cloudnative-pg"
  namespace        = var.namespace
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  version          = "0.23.2"
  create_namespace = false

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      storage_class_name = var.use_longhorn_storage ? "cnpg-longhorn" : ""
    })
  ]
}


