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

# Bootstrap the resource group that will hold everything
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

module "azure_keyvault" {
  source              = "../../modules/azure-keyvault"
  app_name            = "eso-dev"
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
  kubeconfig        = var.kubeconfig
  storage_class     = var.storage_class
  slack_webhook_url = var.slack_webhook_url
}

module "cnpg_operator" {
  source = "../../modules/cnpg-operator"
  namespace = "cnpg"
  kubeconfig  = var.kubeconfig

  depends_on = [module.prometheus-stack]
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

