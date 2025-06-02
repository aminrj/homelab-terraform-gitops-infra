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

module "longhorn" {
  source            = "../../modules/longhorn"
  kubeconfig  = var.kubeconfig
  default_data_path = var.default_data_path
  kubelet_root_dir = var.kubelet_root_dir
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


provider "azurerm" {
  features {}
}

provider "azuread" {}

# Bootstrap the resource group that will hold everything
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

module "azure_keyvault" {
  source              = "../../modules/azure-keyvault"
  app_name            = "eso-prod"
  key_vault_name      = var.key_vault_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  storage_account_name     = var.storage_account_name 
  # storage_connection_string= var.storage_connection_string
}

# the app-storage module will: (for commafeed app)
# Create commafeed-db blob container
# Generate a scoped SAS token
# Store token and container name in Key Vault
locals {
  apps = {
    commafeed = { container_name = "commafeed-db" }
    linkding = { container_name = "linkding-db" }
    wallabag  = { container_name = "wallabag-db" }
  }
}

module "app_storage" {
  for_each             = local.apps
  source               = "../../modules/azure-app-storage"
  container_name       = each.value.container_name
  storage_account_name = module.azure_keyvault.storage_account_name
  connection_string    = module.azure_keyvault.storage_connection_string
  key_vault_id         = module.azure_keyvault.key_vault_id
}

module "commafeed_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "commafeed"

  static_secrets = {
    "db-username" = "commafeed"
    "db-name" = "commafeed"
  }

  random_secrets = [
    "db-password",
    # "api-secret"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}

module "linkding_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "linkding"

  static_secrets = {
    "db-username" = "linkding"
    "db-name" = "linkding"
  }

  random_secrets = [
    "db-password",
    # "api-secret"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}

module "n8n_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "n8n"

  static_secrets = {
    "db-username" = "n8n"
    "db-name" = "n8n"
  }

  random_secrets = [
    "db-password",
    "encryption-key"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}

module "external_secrets" {
  source = "../../modules/external-secrets"
}

module "prometheus-stack" {
  source            = "../../modules/kube-prometheus-stack"
  kubeconfig  = var.kubeconfig
  storage_class = var.storage_class
}

module "cnpg_operator" {
  source = "../../modules/cnpg-operator"
  use_longhorn_storage = true
  # TODO: Move this value to the tfvars instead
  namespace = "cnpg-prod"
  kubeconfig  = var.kubeconfig
}
