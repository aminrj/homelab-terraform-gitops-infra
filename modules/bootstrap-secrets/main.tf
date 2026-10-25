# The two secrets that must exist before GitOps can run, created from Azure instead of by hand:
#
# - azure-creds-prod (external-secrets): the External Secrets Operator's login to Key Vault.
#   A password of its own on the existing ESO app registration (the one the prod env created),
#   rotated every `password_rotation_days`; the prod env's own password is not touched.
# - homelab-gitops-repo (argocd): ArgoCD's deploy key for this repo, read from Key Vault.
#   ESO can't provide it: ESO's own configuration is deployed by ArgoCD.
terraform {
  required_providers {
    azuread    = { source = "hashicorp/azuread" }
    azurerm    = { source = "hashicorp/azurerm" }
    kubernetes = { source = "hashicorp/kubernetes" }
    time       = { source = "hashicorp/time" }
  }
}

# The k8s secrets wait for the charts that create their namespaces (var.wait_for). Only they
# depend on it: a module-level depends_on would defer the data sources below on every chart
# change, and an unknown application_id makes Terraform replace the ESO password each time.
resource "terraform_data" "namespaces_ready" {
  input = var.wait_for
}

data "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group
}

data "azuread_application" "eso" {
  client_id = var.eso_client_id
}

resource "time_rotating" "eso_password" {
  rotation_days = var.password_rotation_days
}

resource "azuread_application_password" "eso_shared" {
  application_id      = data.azuread_application.eso.id
  display_name        = "homelab-gitops-shared (MicroK8s cluster)"
  end_date_relative   = "${(var.password_rotation_days + 30) * 24}h"
  rotate_when_changed = { rotation = time_rotating.eso_password.id }
}

resource "kubernetes_secret" "eso_azure_creds" {
  depends_on = [terraform_data.namespaces_ready]
  metadata {
    name      = "azure-creds-prod"
    namespace = "external-secrets"
  }
  data = {
    "client-id"     = var.eso_client_id
    "client-secret" = azuread_application_password.eso_shared.value
  }
}

data "azurerm_key_vault_secret" "repo_key" {
  name         = "argocd-homelab-repo-ssh-key"
  key_vault_id = data.azurerm_key_vault.this.id
}

resource "kubernetes_secret" "argocd_repo" {
  depends_on = [terraform_data.namespaces_ready]
  metadata {
    name      = "homelab-gitops-repo"
    namespace = "argocd"
    labels    = { "argocd.argoproj.io/secret-type" = "repository" }
  }
  data = {
    type          = "git"
    name          = "homelab-gitops"
    url           = var.repo_url
    sshPrivateKey = data.azurerm_key_vault_secret.repo_key.value
  }
}
