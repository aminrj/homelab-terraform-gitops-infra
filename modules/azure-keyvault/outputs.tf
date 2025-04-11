
output "storage_connection_string" {
  value     = azurerm_storage_account.backup.primary_connection_string
  sensitive = true
}

output "storage_account_name" {
  value = azurerm_storage_account.backup.name
}

output "storage_account_id" {
  value = azurerm_storage_account.backup.id
}

output "client_id" {
  value = azuread_application.eso.client_id
}

output "client_secret" {
  value     = azuread_application_password.eso.value
  sensitive = true
}

output "vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

output "key_vault_id" {
  value = azurerm_key_vault.this.id
}
