output "client_id" {
  value = module.azure_keyvault.client_id
}

output "client_secret" {
  value = module.azure_keyvault.client_secret
  sensitive = true
}

output "vault_uri" {
  value = module.azure_keyvault.vault_uri
}
