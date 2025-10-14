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

# Core Kubernetes resources and basic infrastructure
module "kubernetes" {
  source            = "../../modules/kubernetes"
  kubeconfig  = var.kubeconfig
}

module "priority_classes" {
  source = "../../modules/priority-classes"

  depends_on = [
    module.kubernetes
  ]
}

# MetalLB for LoadBalancer services - depends on kubernetes being ready
module "metallb" {
  source                = "../../modules/metallb"
  kubeconfig            = var.kubeconfig
  metallb_address_range = var.metallb_address_range

  depends_on = [
    module.kubernetes,
    module.priority_classes
  ]
}

# Nginx Ingress Controller - can run independently but better after metallb
module "nginx-ingress-controller" {
  source     = "../../modules/nginx-ingress-controller"
  kubeconfig = var.kubeconfig

  depends_on = [
    module.metallb
  ]
}

# Cert-manager for TLS certificates - needs kubernetes
module "cert-manager" {
  source     = "../../modules/cert-manager"
  kubeconfig = var.kubeconfig

  depends_on = [
    module.kubernetes
  ]
}

# External DNS - keeps Cloudflare DNS in sync with ingresses
module "external-dns" {
  source               = "../../modules/external-dns"
  kubeconfig           = var.kubeconfig
  cloudflare_api_token = var.cloudflare_api_token

  depends_on = [
    module.cert-manager,
    module.metallb
  ]
}

# External Secrets - core infrastructure component
module "external_secrets" {
  source = "../../modules/external-secrets"

  depends_on = [
    module.kubernetes
  ]
}

# Prometheus stack - needs kubernetes and benefits from cert-manager
module "prometheus-stack" {
  source            = "../../modules/kube-prometheus-stack"
  kubeconfig        = var.kubeconfig
  storage_class     = var.storage_class
  slack_webhook_url = var.slack_webhook_url

  depends_on = [
    module.kubernetes,
    module.metallb,
    module.priority_classes
  ]
}

# MicroCeph monitoring - depends on prometheus being available
module "microceph" {
  source = "../../modules/microceph"

  prometheus_release_name   = "kube-prometheus-stack"
  deploy_microceph_tools   = false
  enable_status_checks     = false
  monitoring_namespace     = "monitoring"
  microceph_manager_ip     = "10.0.30.15"  # Current active manager
  slack_webhook_url        = var.slack_webhook_url

  depends_on = [
    module.prometheus-stack
  ]
}

# CNPG Operator - depends on kubernetes and benefits from prometheus
module "cnpg_operator" {
  source     = "../../modules/cnpg-operator"
  namespace  = var.namespace
  kubeconfig = var.kubeconfig

  depends_on = [
    module.kubernetes,
    module.prometheus-stack,
    module.priority_classes
  ]
}

# ArgoCD - depends on basic infrastructure being ready
module "argocd" {
  source                = "../../modules/argocd"
  kubeconfig            = var.kubeconfig
  target_cluster_server = var.target_cluster_server

  depends_on = [
    module.kubernetes,
    module.metallb,
    module.cert-manager,
    module.external_secrets
  ]
}

# ArgoCD Infrastructure - depends on ArgoCD being fully deployed
module "argocd_infrastructure" {
  source     = "../../modules/argocd-infrastructure"
  kubeconfig = var.kubeconfig

  depends_on = [
    module.argocd
  ]
}
