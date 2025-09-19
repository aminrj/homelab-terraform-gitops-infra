terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.53.0"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
    config_context = var.kube_context
    # config_path = "~/.kube/config"
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

