terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
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

