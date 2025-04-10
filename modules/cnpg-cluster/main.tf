# modules/cnpg-cluster/main.tf
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
    name = "cnpg-dev"
  }
}

resource "kubectl_manifest" "cnpg_cluster" {
  yaml_body = templatefile("${path.module}/cluster.yaml.tpl", {
    pg_cluster_name        = var.pg_cluster_name
    pg_namespace           = var.namespace
    pg_instance_count      = var.pg_instance_count
    pg_storage_class       = var.pg_storage_class
    pg_storage_size        = var.pg_storage_size
    pg_superuser_secret    = var.pg_superuser_secret
    pg_app_secret          = var.pg_app_secret
    pg_monitoring_enabled  = var.pg_monitoring_enabled
  })
}
