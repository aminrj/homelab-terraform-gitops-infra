# Terraform + ArgoCD: The Complete GitOps Stack for Kubernetes Infrastructure

*How to combine Terraform's infrastructure provisioning with ArgoCD's application deployment for a complete, declarative Kubernetes platform. Real Terraform code from a production homelab.*

## The Two-Layer Architecture

My homelab infrastructure uses a clear separation of concerns:

**Layer 1: Terraform** - Provisions foundational infrastructure
- Azure resources (Key Vault, Storage, etc.)
- Kubernetes operators (CNPG, External Secrets, Cert Manager)
- ArgoCD installation
- Bootstrap secrets

**Layer 2: ArgoCD** - Manages application lifecycle
- Application deployments
- Database clusters
- Configuration management
- Continuous delivery

```
┌──────────────────────────────────────────┐
│  Terraform (Infrastructure Layer)        │
│  ├─ Azure Key Vault                      │
│  ├─ Storage Accounts (for backups)       │
│  ├─ Kubernetes Operators                 │
│  │  ├─ CNPG Operator                     │
│  │  ├─ External Secrets Operator         │
│  │  ├─ Cert Manager                      │
│  │  └─ MetalLB                            │
│  └─ ArgoCD Installation                  │
└──────────────┬───────────────────────────┘
               │
               │ Handoff: ArgoCD manages everything below
               ▼
┌──────────────────────────────────────────┐
│   ArgoCD (Application Layer)             │
│  ├─ Applications (n8n, commafeed, etc.)  │
│  ├─ Database Clusters (CNPG)             │
│  ├─ External Secrets                     │
│  └─ Infrastructure Config                │
└──────────────────────────────────────────┘
```

## Repository Structure

```
homelab-terraform-gitops-infra/
├── environments/              # Terraform root modules
│   ├── prod/
│   │   ├── main.tf           # Main configuration
│   │   ├── variables.tf      # Input variables
│   │   ├── terraform.tfvars  # Variable values
│   │   └── outputs.tf        # Outputs for ArgoCD
│   ├── qa/
│   └── shared/
│
├── modules/                   # Reusable Terraform modules
│   ├── argocd/               # ArgoCD installation
│   ├── azure-keyvault/       # Azure Key Vault setup
│   ├── azure-app-storage/    # Storage containers for backups
│   ├── azure-secrets/        # Secret management
│   ├── cnpg-operator/        # PostgreSQL operator
│   ├── external-secrets/     # External Secrets operator
│   ├── cert-manager/         # TLS certificate management
│   └── metallb/              # Load balancer
│
├── argocd/                    # ArgoCD configurations (managed by ArgoCD)
│   ├── applicationset.yaml   # Auto-discovery
│   └── ...
│
├── apps/                      # Applications (managed by ArgoCD)
│   ├── n8n/
│   ├── commafeed/
│   └── ...
│
└── databases/                 # Database clusters (managed by ArgoCD)
    ├── n8n/
    └── ...
```

## Terraform Configuration

### Main Environment Configuration

```hcl
# environments/prod/main.tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5"
    }
  }

  # Store Terraform state in Azure
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "terraformstatehomelab"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig
    config_context = var.kube_context
  }
}

# Bootstrap resource group for all Azure resources
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = "prod"
    managed-by  = "terraform"
    project     = "homelab"
  }
}

# Azure Key Vault for storing secrets
module "azure_keyvault" {
  source               = "../../modules/azure-keyvault"
  app_name             = var.app_name
  key_vault_name       = var.key_vault_name
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_name = var.storage_account_name
}

# Create storage containers for each app's backups
locals {
  apps = {
    commafeed = { container_name = "commafeed-db-clean" }
    linkding  = { container_name = "linkding-db-clean" }
    wallabag  = { container_name = "wallabag-db-clean" }
    n8n       = { container_name = "n8n-db-clean" }
    listmonk  = { container_name = "listmonk-db-clean" }
  }
}

module "app_storage" {
  for_each             = local.apps
  source               = "../../modules/azure-app-storage"
  container_name       = each.value.container_name
  storage_account_name = module.azure_keyvault.storage_account_name
  connection_string    = module.azure_keyvault.storage_connection_string
  key_vault_id         = module.azure_keyvault.key_vault_id
}

# Generate and store database credentials
module "n8n_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "n8n"

  static_secrets = {
    "db-username" = "n8n"
    "db-name"     = "n8n"
  }

  random_secrets = [
    "db-password",
    "encryption-key"
  ]

  depends_on = [module.azure_keyvault]
}

module "commafeed_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "commafeed"

  static_secrets = {
    "db-username" = "commafeed"
    "db-name"     = "commafeed"
  }

  random_secrets = ["db-password"]
  depends_on     = [module.azure_keyvault]
}

# Install Kubernetes operators
module "cnpg_operator" {
  source     = "../../modules/cnpg-operator"
  depends_on = [module.azure_keyvault]
}

module "external_secrets" {
  source     = "../../modules/external-secrets"
  depends_on = [module.azure_keyvault]
}

module "cert_manager" {
  source     = "../../modules/cert-manager"
  depends_on = [module.azure_keyvault]
}

module "metallb" {
  source         = "../../modules/metallb"
  ip_range_start = "192.168.1.200"  # Adjust for your network
  ip_range_end   = "192.168.1.250"
}

# Install ArgoCD (this will then manage everything else)
module "argocd" {
  source              = "../../modules/argocd"
  argocd_namespace    = "argocd"
  target_cluster_server = "https://kubernetes.default.svc"

  depends_on = [
    module.cnpg_operator,
    module.external_secrets,
    module.cert_manager
  ]
}
```

### Variables

```hcl
# environments/prod/variables.tf
variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Azure resource group name"
  type        = string
  default     = "homelab-prod-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "key_vault_name" {
  description = "Azure Key Vault name"
  type        = string
}

variable "storage_account_name" {
  description = "Azure Storage Account name"
  type        = string
}

variable "app_name" {
  description = "Application name prefix"
  type        = string
  default     = "homelab"
}

variable "kubeconfig" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/microk8s-config"
}

variable "kube_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "microk8s"
}
```

```hcl
# environments/prod/terraform.tfvars
subscription_id      = "your-azure-subscription-id"
key_vault_name       = "homelab-keyvault-prod"
storage_account_name = "homelabstorageaccntprod"
```

### Outputs

```hcl
# environments/prod/outputs.tf
output "key_vault_name" {
  description = "Azure Key Vault name for ArgoCD/apps to reference"
  value       = module.azure_keyvault.key_vault_name
}

output "storage_account_name" {
  description = "Storage account for CNPG backups"
  value       = module.azure_keyvault.storage_account_name
}

output "resource_group_name" {
  description = "Resource group containing all resources"
  value       = azurerm_resource_group.main.name
}

# Don't expose in logs - use terraform output command
output "argocd_admin_password" {
  description = "ArgoCD admin password"
  value       = module.argocd.admin_password
  sensitive   = true
}
```

## Terraform Modules

### ArgoCD Module

```hcl
# modules/argocd/main.tf
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.5"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }
  }
}

# Install ArgoCD using Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = var.argocd_namespace
  chart      = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  version    = "5.46.0"

  create_namespace = true

  values = [file("${path.module}/values.yaml")]

  wait = false
}

# Make ArgoCD self-managing (it manages its own configuration from Git)
resource "kubectl_manifest" "argocd_self_managed" {
  depends_on = [helm_release.argocd]

  yaml_body = templatefile("${path.module}/argocd-config.yaml", {
    TARGET_SERVER = var.target_cluster_server
  })
}
```

```yaml
# modules/argocd/argocd-config.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/aminrj/homelab-terraform-gitops-infra.git
    targetRevision: main
    path: argocd
  destination:
    server: ${TARGET_SERVER}
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

```hcl
# modules/argocd/variables.tf
variable "argocd_namespace" {
  description = "Namespace to install ArgoCD"
  type        = string
  default     = "argocd"
}

variable "target_cluster_server" {
  description = "Kubernetes API server URL"
  type        = string
  default     = "https://kubernetes.default.svc"
}
```

### External Secrets Module

```hcl
# modules/external-secrets/main.tf
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.15.1"

  values = [
    yamlencode({
      installCRDs = true

      # Required to process ClusterSecretStores across namespaces
      processClusterStore          = true
      processClusterExternalSecret = true

      # Full cluster RBAC permissions
      rbac = {
        create      = true
        clusterWide = true
      }

      serviceAccount = {
        create = true
        name   = "external-secrets-sa"
      }

      webhook = {
        create = true
      }

      certController = {
        create = true
      }
    })
  ]
}
```

### Azure Key Vault Module

```hcl
# modules/azure-keyvault/main.tf
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  enable_rbac_authorization = true
  purge_protection_enabled  = false  # Set true in production

  tags = {
    environment = var.app_name
    managed-by  = "terraform"
  }
}

resource "azurerm_storage_account" "main" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = var.app_name
    managed-by  = "terraform"
  }
}

# Grant Terraform service principal access to Key Vault
resource "azurerm_role_assignment" "keyvault_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "vault_url" {
  value = azurerm_key_vault.main.vault_uri
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "storage_connection_string" {
  value     = azurerm_storage_account.main.primary_connection_string
  sensitive = true
}
```

### Azure Secrets Module

```hcl
# modules/azure-secrets/main.tf
resource "random_password" "passwords" {
  for_each = toset(var.random_secrets)

  length  = 32
  special = true
}

resource "azurerm_key_vault_secret" "static" {
  for_each = var.static_secrets

  name         = "${var.app_name}-${each.key}"
  value        = each.value
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "random" {
  for_each = toset(var.random_secrets)

  name         = "${var.app_name}-${each.key}"
  value        = random_password.passwords[each.key].result
  key_vault_id = var.key_vault_id
}
```

## The Handoff: Terraform → ArgoCD

The critical part is the handoff between Terraform and ArgoCD. Here's how it works:

### 1. Terraform Creates Infrastructure

```bash
cd environments/prod
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply
```

This creates:
- Azure Key Vault with secrets
- Storage containers for backups
- CNPG operator
- External Secrets operator
- ArgoCD installation

### 2. ArgoCD Becomes Self-Managing

The `argocd_self_managed` resource creates an ArgoCD Application that points to the `/argocd` directory in Git. This makes ArgoCD manage its own ApplicationSets:

```yaml
# Created by Terraform, then managed by ArgoCD
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/aminrj/homelab-terraform-gitops-infra.git
    path: argocd  # ArgoCD manages files in this directory
```

### 3. ApplicationSets Auto-Discover Apps

ArgoCD reads ApplicationSets from Git and auto-creates applications:

```yaml
# argocd/applicationset.yaml (managed by ArgoCD, not Terraform)
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps
spec:
  generators:
    - git:
        directories:
          - path: apps/*/overlays/*
  template:
    metadata:
      name: '{{path[1]}}-{{path[3]}}'
    spec:
      source:
        path: 'apps/{{path[1]}}/overlays/{{path[3]}}'
```

### 4. Applications Deploy

ArgoCD deploys applications found in the `apps/` directory without any Terraform intervention.

## Deployment Workflow

### Initial Setup

```bash
# 1. Clone repository
git clone https://github.com/aminrj/homelab-terraform-gitops-infra.git
cd homelab-terraform-gitops-infra

# 2. Configure Azure credentials
az login
az account set --subscription "your-subscription-id"

# 3. Create Terraform backend storage
az group create --name terraform-state-rg --location eastus
az storage account create \
  --name terraformstatehomelab \
  --resource-group terraform-state-rg \
  --sku Standard_LRS
az storage container create \
  --name tfstate \
  --account-name terraformstatehomelab

# 4. Update terraform.tfvars with your values
cd environments/prod
cp terraform.tfvars.example terraform.tfvars
# Edit with your subscription ID, etc.

# 5. Initialize and apply Terraform
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply

# 6. Get ArgoCD admin password
terraform output -raw argocd_admin_password

# 7. Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
# Username: admin
# Password: (from terraform output)

# 8. Watch ArgoCD auto-discover and deploy apps
kubectl get applications -n argocd -w
```

### Adding a New Application

```bash
# Create application structure
mkdir -p apps/newapp/{base,overlays/prod}

# Add base configuration
cat > apps/newapp/base/kustomization.yaml <<EOF
resources:
  - deployment.yaml
  - service.yaml
EOF

# Add production overlay
cat > apps/newapp/overlays/prod/kustomization.yaml <<EOF
namespace: newapp-prod
resources:
  - ../../base
  - ingress.yaml
EOF

# Commit and push
git add apps/newapp
git commit -m "Add newapp"
git push

# ArgoCD auto-discovers within 3 minutes
# Or sync immediately via UI/CLI
argocd app sync newapp-prod
```

### Updating Infrastructure

```bash
# Infrastructure changes go through Terraform
cd environments/prod

# Add new module or update existing
vim main.tf

# Plan and apply
terraform plan -var-file="terraform.tfvars"
terraform apply

# Applications continue running during Terraform updates
```

## Best Practices

### 1. Clear Separation

**Terraform manages:**
- ✅ Cloud provider resources (Azure, AWS, GCP)
- ✅ Kubernetes operators and CRDs
- ✅ Initial ArgoCD installation
- ✅ Bootstrap secrets for ArgoCD

**ArgoCD manages:**
- ✅ Application deployments
- ✅ Database clusters
- ✅ External Secrets (referencing Terraform-created vault)
- ✅ Configuration changes

### 2. Use Terraform Outputs

```hcl
output "key_vault_name" {
  value = module.azure_keyvault.key_vault_name
}
```

Reference in ExternalSecret (deployed by ArgoCD):

```yaml
spec:
  provider:
    azurekv:
      vaultUrl: https://homelab-keyvault-prod.vault.azure.net/
      # Use the Key Vault created by Terraform
```

### 3. Remote State for Cross-Environment

```hcl
# environments/qa/main.tf
data "terraform_remote_state" "prod" {
  backend = "azurerm"
  config = {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "terraformstatehomelab"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
  }
}

# Reference prod Key Vault from QA
vault_url = data.terraform_remote_state.prod.outputs.vault_url
```

### 4. Version Pin Everything

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 3.75.0"  # Pin exact version
    }
  }
}
```

## Troubleshooting

### Issue: ArgoCD Not Self-Managing

**Symptom:** ArgoCD Application for argocd not created

**Debug:**
```bash
kubectl get applications -n argocd
# argocd application missing

kubectl get applications -n argocd argocd -o yaml
# Check for errors
```

**Fix:**
```bash
# Manually apply ArgoCD self-management
kubectl apply -f modules/argocd/argocd-config.yaml

# Or re-run Terraform
terraform apply -target=module.argocd
```

### Issue: Terraform Can't Connect to Cluster

**Error:** `Error: Kubernetes cluster unreachable`

**Fix:**
```bash
# Verify kubeconfig
export KUBECONFIG=~/.kube/microk8s-config
kubectl cluster-info

# Test connection
kubectl get nodes

# Update Terraform provider
provider "kubernetes" {
  config_path = pathexpand("~/.kube/microk8s-config")
}
```

### Issue: Azure Provider Authentication

**Error:** `Error: building account: could not acquire access token`

**Fix:**
```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-sub-id"

# Verify
az account show
```

## Complete Setup Script

```bash
#!/bin/bash
set -euo pipefail

echo "==> Setting up homelab GitOps infrastructure"

# Prerequisites check
command -v az >/dev/null 2>&1 || { echo "Azure CLI required"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Terraform required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl required"; exit 1; }

# Azure login
echo "==> Logging into Azure"
az login
az account set --subscription "${AZURE_SUBSCRIPTION_ID}"

# Create Terraform backend
echo "==> Creating Terraform backend"
az group create --name terraform-state-rg --location eastus
az storage account create \
  --name terraformstatehomelab \
  --resource-group terraform-state-rg \
  --sku Standard_LRS
az storage container create \
  --name tfstate \
  --account-name terraformstatehomelab

# Deploy infrastructure
echo "==> Deploying Terraform infrastructure"
cd environments/prod
terraform init
terraform apply -var-file="terraform.tfvars" -auto-approve

# Get ArgoCD password
echo "==> ArgoCD Admin Password:"
terraform output -raw argocd_admin_password

echo "==> Setup complete!"
echo "Access ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
```

## Conclusion

Terraform + ArgoCD provides production-grade GitOps:

**Benefits:**
- Clear separation of concerns
- Infrastructure as Code for cloud resources
- GitOps for application management
- Self-service app deployment
- Disaster recovery via Git

**Key Patterns:**
- Terraform creates foundation
- ArgoCD becomes self-managing
- ApplicationSets auto-discover apps
- Git as single source of truth

This architecture scales from homelabs to production.

---

**Related Reading:**
- [ArgoCD ApplicationSets](#) - Auto-discovery patterns
- [External Secrets + CNPG](#) - Secret management
- [GitOps Disaster Recovery](#) - Recovery from Git

**Code Repository:** [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
