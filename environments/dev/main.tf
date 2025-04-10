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


provider "azurerm" {
  features {}
}

provider "azuread" {}

# the app-storage module will: (for commafeed app)
# Create commafeed-db blob container
# Generate a scoped SAS token
# Store token and container name in Key Vault


locals {
  apps = {
    commafeed = { container_name = "commafeed-db" }
    # wallabag  = { container_name = "wallabag-db" }
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

module "azure_keyvault" {
  source              = "../../modules/azure-keyvault"
  app_name            = "eso-dev"
  key_vault_name      = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name 
  storage_account_name     = var.storage_account_name 
  # storage_connection_string= var.storage_connection_string
}

module "commafeed_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "commafeed"

  static_secrets = {
    "db-username" = "commafeed"
  }

  random_secrets = [
    "db-password",
    # "api-secret"
  ]
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
  namespace = "cnpg"
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

