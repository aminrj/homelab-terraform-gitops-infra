# Remote state in Azure Storage, the same account as homelab-foundation. Settings in
# backend.hcl (gitignored; copy backend.hcl.example). `make shared-init` runs the init.
terraform {
  backend "azurerm" {}
}
