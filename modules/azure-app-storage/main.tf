data "azurerm_storage_account" "app" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_storage_container" "app" {
  name                  = var.container_name
  storage_account_id    = data.azurerm_storage_account.app.id
  container_access_type = "private"
}

# SAS rotation anchor.
#
# This was previously `time_static`, which records its timestamp once at create
# and never moves again. Combined with a 365-day expiry that guaranteed every SAS
# token would silently expire exactly one year after first apply and take all
# CNPG WAL archiving down with it — which is what happened on 2026-06-24.
#
# time_rotating re-generates every rotation_days, so a plain `terraform apply`
# after that window mints a fresh token. rotation (300d) is deliberately shorter
# than expiry (365d) to leave ~65 days of overlap.
resource "time_rotating" "sas_start" {
  rotation_days = 300
}

data "azurerm_storage_account_sas" "app_sas" {
  connection_string = var.connection_string
  signed_version    = "2022-11-02"

  https_only = true
  start      = time_rotating.sas_start.rfc3339
  expiry     = timeadd(time_rotating.sas_start.rfc3339, "8760h")

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

  # NO ignore_changes here, deliberately. It used to be set, which meant that
  # even once a fresh SAS was generated Terraform would refuse to write it to
  # Key Vault — the rotation above would have been silently useless. The whole
  # point of this secret is that its value changes on rotation.
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
