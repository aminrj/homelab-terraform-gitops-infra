data "azurerm_client_config" "current" {}

resource "azuread_application" "eso" {
  display_name = var.app_name
}

resource "azuread_service_principal" "eso" {
  client_id = azuread_application.eso.client_id
}

resource "azuread_application_password" "eso" {
  application_id = azuread_application.eso.id
}

resource "azurerm_key_vault" "this" {
  name                        = var.key_vault_name
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  enable_rbac_authorization   = true
}


resource "azurerm_storage_account" "backup" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# External Secrets Operator app
resource "azurerm_role_assignment" "eso_secret_reader" {
  principal_id         = azuread_service_principal.eso.id
  role_definition_name = "Key Vault Secrets User"
  scope                = azurerm_key_vault.this.id
}

# Add Role Assignment for the Terraform Caller
resource "azurerm_role_assignment" "terraform_secret_writer" {
  principal_id         = data.azurerm_client_config.current.object_id
  role_definition_name = "Key Vault Secrets Officer"
  scope                = azurerm_key_vault.this.id
}
# Now both the ESO identity and the Terraform runner can access the vault appropriately.
