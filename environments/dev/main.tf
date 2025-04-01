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

provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig
    config_context = var.kube_context
  }
}

provider "kubectl" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}

module "argocd" {
  source = "../../modules/argocd"
  kubeconfig = var.kubeconfig
  target_cluster_server = var.target_cluster_server

  providers = {
    kubernetes = kubernetes
    helm       = helm
    kubectl    = kubectl
  }
}

module "prometheus-stack" {
  source            = "../../modules/kube-prometheus-stack"
  kubeconfig  = var.kubeconfig
  storage_class = var.storage_class
}

module "cnpg_operator" {
  source = "../../modules/cnpg-operator"
  use_longhorn_storage = false
  namespace = "cnpg-dev"
  kubeconfig  = var.kubeconfig
}

module "cnpg_cluster" {
  source = "../../modules/cnpg-cluster"

  namespace             = "cnpg-dev"
  pg_cluster_name       = "pg-dev"
  pg_instance_count     = 1
  pg_storage_class      = "local-path"
  pg_storage_size       = "5Gi"
  pg_superuser_secret   = "pg-superuser-dev"
  pg_app_secret         = "pg-app-dev"
  pg_monitoring_enabled = true
}

