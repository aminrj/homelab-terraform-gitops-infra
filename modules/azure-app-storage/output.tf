output "destination_path" {
  value = "https://${var.storage_account_name}.blob.core.windows.net/${var.container_name}"
}

output "container_name" {
  value = azurerm_storage_container.app.name
}

output "storage_account_name" {
  value = data.azurerm_storage_account.app.name
}
