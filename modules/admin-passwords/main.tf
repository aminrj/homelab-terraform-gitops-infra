# Admin passwords for the platform UIs: generated here, kept in Key Vault (read them there),
# handed to the charts. ArgoCD only ever gets the bcrypt hash.
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    time    = { source = "hashicorp/time" }
  }
}

data "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group
}

resource "random_password" "this" {
  for_each = toset(["argocd", "grafana"])
  length   = 32
  special  = false
}

resource "azurerm_key_vault_secret" "this" {
  for_each     = random_password.this
  name         = "gitops-${each.key}-admin-password"
  value        = each.value.result
  content_type = "${each.key} UI, user admin (managed by terraform, environments/shared)"
  key_vault_id = data.azurerm_key_vault.this.id
}

# Changes only with the password: ArgoCD ends existing sessions when this time moves.
resource "time_static" "argocd_password" {
  triggers = { password = sha256(random_password.this["argocd"].result) }
}
