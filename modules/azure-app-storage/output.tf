output "destination_path" {
  value = "https://${var.storage_account_name}.blob.core.windows.net/${var.container_name}"
}
