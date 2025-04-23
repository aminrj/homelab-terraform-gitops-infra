resource "azurerm_storage_container" "app" {
  name                  = var.container_name
  storage_account_name  = var.storage_account_name
  container_access_type = "private"
}

resource "time_static" "sas_start" {}

data "azurerm_storage_account_sas" "app_sas" {
  connection_string = var.connection_string
  signed_version    = "2022-11-02"

  https_only = true
  start      = time_static.sas_start.rfc3339
  expiry     = timeadd(time_static.sas_start.rfc3339, "8760h")

  resource_types {
    service   = true
    container = true
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  permissions {
    read    = true
    write   = true
    delete  = true
    list    = true
    add     = true
    create  = true
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

resource "azurerm_key_vault_secret" "sas_token" {
  name         = "${var.container_name}-blob-sas"
  value        = data.azurerm_storage_account_sas.app_sas.sas
  key_vault_id = var.key_vault_id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_key_vault_secret" "container_name" {
  name         = "${var.container_name}-container-name"
  value        = var.container_name
  key_vault_id = var.key_vault_id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_key_vault_secret" "destination_path" {
  name         = "${var.container_name}-destination-path"
  value        = "https://${var.storage_account_name}.blob.core.windows.net/${var.container_name}"
  key_vault_id = var.key_vault_id

  lifecycle {
    ignore_changes = [value]
  }
}

