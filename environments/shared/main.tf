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
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source = "hashicorp/azuread"
      version = "~> 2.0"
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

module "kubernetes" {
  source            = "../../modules/kubernetes"
  kubeconfig  = var.kubeconfig
}

module "metallb" {
  source            = "../../modules/metallb"
  kubeconfig  = var.kubeconfig
  metallb_address_range = var.metallb_address_range
}

module "nginx-ingress-controller" {
  source            = "../../modules/nginx-ingress-controller"
  kubeconfig  = var.kubeconfig
}

module "argocd" {
  source            = "../../modules/argocd"
  kubeconfig  = var.kubeconfig
  target_cluster_server = var.target_cluster_server

}


module "external-dns" {
  source            = "../../modules/external-dns"
  kubeconfig  = var.kubeconfig

  cloudflare_api_token = var.cloudflare_api_token
}

module "cert-manager" {
  source            = "../../modules/cert-manager"
  kubeconfig  = var.kubeconfig
}


module "external_secrets" {
  source = "../../modules/external-secrets"
}

module "prometheus-stack" {
  source            = "../../modules/kube-prometheus-stack"
  kubeconfig  = var.kubeconfig
  storage_class = var.storage_class
  slack_webhook_url = var.slack_webhook_url
}

module "cnpg_operator" {
  source = "../../modules/cnpg-operator"
  # TODO: Move this value to the tfvars instead
  namespace = var.namespace
  kubeconfig  = var.kubeconfig
}

