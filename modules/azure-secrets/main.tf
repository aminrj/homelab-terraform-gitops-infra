resource "azurerm_key_vault_secret" "static" {
  for_each     = var.static_secrets
  name         = "${var.app_name}-${each.key}"
  value        = each.value
  key_vault_id = var.key_vault_id
}

resource "random_password" "random" {
  for_each = toset(var.random_secrets)
  length   = 32
  special  = true
}

resource "azurerm_key_vault_secret" "generated" {
  for_each     = random_password.random
  name         = "${var.app_name}-${each.key}"
  value        = each.value.result
  key_vault_id = var.key_vault_id
}
