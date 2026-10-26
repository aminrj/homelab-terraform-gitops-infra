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
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

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
  source     = "../../modules/kubernetes"
  kubeconfig = var.kubeconfig
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

# Ingress: Traefik on the ingress VIP (ingress-nginx is retired upstream since 2026-03).
module "traefik" {
  source           = "../../modules/traefik"
  load_balancer_ip = var.ingress_vip

  depends_on = [
    module.metallb
  ]
}

# Cert-manager for TLS certificates - needs kubernetes
module "cert-manager" {
  source               = "../../modules/cert-manager"
  kubeconfig           = var.kubeconfig
  cloudflare_api_token = var.cloudflare_api_token

  depends_on = [
    module.kubernetes
  ]
}

# External DNS - keeps Cloudflare DNS in sync with ingresses. Off until the Cloudflare
# token is in Key Vault (gitops-cloudflare-api-token) and enable_external_dns = true.
module "external-dns" {
  count                = var.enable_external_dns ? 1 : 0
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

# Secrets GitOps needs before it can run (ESO's Key Vault login, ArgoCD's repo key).
module "bootstrap_secrets" {
  source                   = "../../modules/bootstrap-secrets"
  key_vault_name           = var.key_vault_name
  key_vault_resource_group = var.key_vault_resource_group
  eso_client_id            = var.eso_client_id
  wait_for                 = [module.external_secrets.namespace, module.argocd.namespace]
}

# ArgoCD and Grafana admin passwords: generated, stored in Key Vault, given to the charts.
module "admin_passwords" {
  source                   = "../../modules/admin-passwords"
  key_vault_name           = var.key_vault_name
  key_vault_resource_group = var.key_vault_resource_group
}

# Prometheus stack - needs kubernetes and benefits from cert-manager
module "prometheus-stack" {
  source                 = "../../modules/kube-prometheus-stack"
  kubeconfig             = var.kubeconfig
  storage_class          = var.storage_class
  slack_webhook_url      = var.slack_webhook_url
  grafana_admin_password = module.admin_passwords.grafana_password

  depends_on = [
    module.kubernetes,
    module.metallb,
    module.priority_classes
  ]
}

# MicroCeph removed 2026-07-22. Ceph was never actually serving volumes: zero PVs
# were ever provisioned on the microceph-rbd StorageClass, its provisioner
# (rbd.csi.ceph.com) never matched the registered CSI drivers
# (rook-ceph.rbd.csi.ceph.com), and no Ceph or Rook pods were running. The module
# only ever created a ServiceMonitor, a headless Service pointing at 10.0.30.15
# (a host that is down), and alert rules that could only ever report no-data.
# All storage is local-path, which is now the default StorageClass.

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
  kube_context          = var.kube_context
  target_cluster_server = var.target_cluster_server
  admin_password_bcrypt = module.admin_passwords.argocd_bcrypt
  admin_password_mtime  = module.admin_passwords.argocd_mtime

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
