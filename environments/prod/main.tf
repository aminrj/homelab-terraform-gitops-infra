provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azuread" {}

# Bootstrap the resource group that will hold everything
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}

module "azure_keyvault" {
  source               = "../../modules/azure-keyvault"
  app_name             = var.app_name
  key_vault_name       = var.key_vault_name
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_name = var.storage_account_name
}

locals {
  apps = {
    commafeed    = { container_name = "commafeed-db-clean" }
    linkding     = { container_name = "linkding-db-clean" }
    wallabag     = { container_name = "wallabag-db-clean" }
    n8n          = { container_name = "n8n-db-clean" }
    listmonk     = { container_name = "listmonk-db-clean" }
    threat_intel = { container_name = "threatintel-data" }
    gitea        = { container_name = "gitea-db-clean" }
  }
}

module "app_storage" {
  for_each             = local.apps
  source               = "../../modules/azure-app-storage"
  container_name       = each.value.container_name
  storage_account_name = module.azure_keyvault.storage_account_name
  resource_group_name  = azurerm_resource_group.main.name
  connection_string    = module.azure_keyvault.storage_connection_string
  key_vault_id         = module.azure_keyvault.key_vault_id
}

module "threat_intel_db_storage" {
  source               = "../../modules/azure-app-storage"
  container_name       = "threat-intel-db-clean"
  storage_account_name = module.azure_keyvault.storage_account_name
  resource_group_name  = azurerm_resource_group.main.name
  connection_string    = module.azure_keyvault.storage_connection_string
  key_vault_id         = module.azure_keyvault.key_vault_id
}

module "linkding_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "linkding"

  static_secrets = {
    "db-username" = "linkding"
    "db-name"     = "linkding"
  }

  random_secrets = [
    "db-password"
  ]
}

module "commafeed_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "commafeed"

  static_secrets = {
    "db-username" = "commafeed"
    "db-name"     = "commafeed"
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
    "db-name"     = "n8n"
  }

  random_secrets = [
    "db-password",
    "encryption-key"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}

module "listmonk_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "listmonk"

  static_secrets = {
    "db-username" = "listmonk"
    "db-name"     = "listmonk"
  }

  random_secrets = [
    "db-password",
  ]

  depends_on = [
    module.azure_keyvault
  ]
}

module "wallabag_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "wallabag"

  static_secrets = {
    "db-username" = "wallabag"
    "db-name"     = "wallabag"
  }

  random_secrets = [
    "db-password",
    # "api-secret"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}

module "wallabag_admin_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "wallabag-admin"

  static_secrets = {
    "username" = "admin"
    "email"    = "admin@example.com"
  }

  random_secrets = [
    "password"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}

module "threat_intel_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "threat-intel"

  static_secrets = {
    "db-username"       = "threatintel"
    "db-name"           = "threatintel"
    "db-host"           = "threat-intel-db-cnpg-v1-rw.cnpg-prod.svc.cluster.local"
    "vt-api-key"        = var.threat_intel_vt_api_key
    "shodan-api-key"    = var.threat_intel_shodan_api_key
    "abuseipdb-api-key" = var.threat_intel_abuseipdb_api_key
    "openai-api-key"    = var.threat_intel_openai_api_key
    "ollama-host"       = var.threat_intel_ollama_host
    "azure-container"   = var.threat_intel_azure_container
    "n8n-db-host"       = "threat-intel-db-cnpg-v1-rw.cnpg-prod.svc.cluster.local"
    "n8n-db-name"       = "threatintel"
    "n8n-db-username"   = "n8n_collector"
    "n8n-db-port"       = "5432"
  }

  random_secrets = [
    "db-password",
    "n8n-user-password",
    "n8n-db-password"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}

module "gitea_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "gitea"

  static_secrets = {
    "db-username" = "gitea"
    "db-name"     = "gitea"
  }

  random_secrets = [
    "db-password",
    "secret-key",
    "internal-token"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}
