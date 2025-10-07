# Homelab Infrastructure GitOps Repository

This repository manages a Kubernetes homelab infrastructure using GitOps with Terraform, ArgoCD, and Azure integration. It manages a MicroK8s cluster with various applications and infrastructure components across multiple environments (dev, qa, prod).

## Architecture Overview

### Core Components
- **Terraform Modules**: Reusable infrastructure components in `/modules/`
- **Environment Management**: Multi-environment setup in `/environments/` (dev, qa, prod, shared)
- **GitOps with ArgoCD**: Automated deployment and synchronization
- **Azure Integration**: Key Vault for secrets, storage for backups
- **PostgreSQL with CNPG**: CloudNative-PG operator for database management
- **Observability Stack**: Prometheus, monitoring, and alerting

### Key Architecture Patterns
1. **Multi-Environment**: Environment isolation using Terraform workspaces and Kustomize overlays
2. **GitOps Flow**: ArgoCD watches this repository and auto-deploys changes to Kubernetes
3. **Secrets Management**: Azure Key Vault integration with External Secrets Operator
4. **Database Management**: PostgreSQL clusters managed by CloudNative-PG operator
5. **Backup Strategy**: Automated database backups to Azure storage
6. **Application Structure**: Kustomize base + overlays pattern for environment-specific configurations

## Bootstrap Instructions

### Prerequisites

1. **MicroK8s Cluster**: Running and accessible via kubectl
2. **Azure CLI**: Installed and authenticated
3. **Terraform**: Version 1.5+ installed
4. **Git Repository**: Fork of this repository with your configurations

### Step 1: Azure Authentication

```bash
# Login to Azure CLI
az logout
az login --tenant "YOUR-TENANT-ID" --scope "https://graph.microsoft.com/.default"

# Verify authentication
az account show
```

### Step 2: Bootstrap Shared Environment

The shared environment contains core infrastructure components that are used across all environments.

```bash
# Navigate to shared environment
cd environments/shared

# Initialize Terraform
terraform init

# Export dummy Cloudflare token to prevent validation errors
export CLOUDFLARE_API_TOKEN="dummy-token-for-terraform-validation"

# Plan and apply
terraform plan -var-file="terraform.tfvars"
terraform apply -auto-approve
```

**Expected Resources Created:**
- MetalLB (Load Balancer)
- cert-manager (TLS certificates)
- External Secrets Operator
- nginx-ingress-controller
- Prometheus monitoring stack
- ArgoCD (GitOps controller)
- CloudNative-PG operator

### Step 3: Import Existing Azure Resources (if applicable)

If you have existing Azure storage containers and secrets, import them into Terraform state:

```bash
# Navigate to production environment
cd environments/prod

# Initialize Terraform
terraform init

# Import existing storage containers (replace with your actual container URLs)
echo "dummy-token-for-terraform-validation" | terraform import 'module.app_storage["n8n"].azurerm_storage_container.app' "https://YOUR-STORAGE-ACCOUNT.blob.core.windows.net/n8n-db-clean"

echo "dummy-token-for-terraform-validation" | terraform import 'module.app_storage["listmonk"].azurerm_storage_container.app' "https://YOUR-STORAGE-ACCOUNT.blob.core.windows.net/listmonk-db-clean"

echo "dummy-token-for-terraform-validation" | terraform import 'module.app_storage["linkding"].azurerm_storage_container.app' "https://YOUR-STORAGE-ACCOUNT.blob.core.windows.net/linkding-db-clean"

echo "dummy-token-for-terraform-validation" | terraform import 'module.app_storage["commafeed"].azurerm_storage_container.app' "https://YOUR-STORAGE-ACCOUNT.blob.core.windows.net/commafeed-db-clean"

echo "dummy-token-for-terraform-validation" | terraform import 'module.app_storage["wallabag"].azurerm_storage_container.app' "https://YOUR-STORAGE-ACCOUNT.blob.core.windows.net/wallabag-db-clean"
```

### Step 4: Deploy Production Environment

```bash
# Still in environments/prod directory
# Deploy production infrastructure
echo "dummy-token-for-terraform-validation" | terraform apply --auto-approve
```

**Expected Resources Created:**
- Azure Key Vault with secrets
- Azure Storage Account and containers
- Service Principal for External Secrets Operator
- Database credentials and backup configurations

### Step 5: Configure External Secrets Operator

After both shared and prod environments are deployed, configure the External Secrets Operator:

```bash
# Navigate to production environment to get outputs
cd environments/prod

# Create External Secrets namespace (if not exists)
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

# Create Azure credentials secret for External Secrets Operator
kubectl create secret generic azure-creds \
  -n external-secrets \
  --from-literal=client-id="$(terraform output -raw client_id)" \
  --from-literal=client-secret="$(terraform output -raw client_secret)"
```

### Step 6: Verify Deployment

```bash
# Check ArgoCD status
kubectl get pods -n argocd

# Check ArgoCD Applications
kubectl get applications -n argocd

# Check External Secrets status
kubectl get externalsecrets --all-namespaces

# Check cluster secret stores
kubectl get clustersecretstores

# Access ArgoCD UI (get LoadBalancer IP)
kubectl get svc argocd-server -n argocd
```

### Step 7: Deploy Additional Environments (Optional)

For dev and qa environments:

```bash
# Dev environment
cd environments/dev
terraform init
echo "dummy-token-for-terraform-validation" | terraform apply --auto-approve

# QA environment  
cd environments/qa
terraform init
echo "dummy-token-for-terraform-validation" | terraform apply --auto-approve
```

## Troubleshooting

### Common Issues

1. **Terraform State Lock**: If terraform commands fail with state lock errors:
   ```bash
   terraform force-unlock LOCK-ID
   ```

2. **Azure Authentication Expired**: 
   ```bash
   az logout
   az login --tenant "YOUR-TENANT-ID" --scope "https://graph.microsoft.com/.default"
   ```

3. **Namespace Already Exists**: Import existing namespaces:
   ```bash
   terraform import module.kubernetes.kubernetes_namespace.NAMESPACE_NAME NAMESPACE_NAME
   ```

4. **External Secrets Not Syncing**: Check cluster secret store status:
   ```bash
   kubectl describe clustersecretstore azure-kv-store-prod
   ```

### Accessing Services

- **ArgoCD UI**: Get LoadBalancer IP and access via browser
- **Grafana**: Check monitoring namespace for Grafana service
- **Applications**: Deployed via ArgoCD ApplicationSets automatically

## Development Workflow

### Making Changes

1. **Infrastructure Changes**: Modify Terraform modules and apply via `terraform apply`
2. **Application Changes**: Update Kustomize configurations; ArgoCD will auto-sync
3. **Database Changes**: Modify database overlays; ArgoCD manages CNPG clusters

### Environment-Specific Configurations

- **Base Configurations**: Located in `base/` directories
- **Environment Overlays**: Located in `overlays/{environment}/` directories
- **Terraform Variables**: Environment-specific variables in `terraform.tfvars`

## Repository Structure

```
├── environments/        # Environment-specific Terraform configurations
│   ├── shared/         # Shared infrastructure (ArgoCD, monitoring, etc.)
│   ├── dev/            # Development environment
│   ├── qa/             # QA environment
│   └── prod/           # Production environment
├── modules/            # Reusable Terraform modules
├── apps/               # Application Kustomize configurations
├── databases/          # Database Kustomize configurations
├── infrastructure/     # Core infrastructure Kustomize configs
├── argocd/            # ArgoCD Application definitions
└── scripts/           # Automation and deployment scripts
```

## Important Notes

- **GitOps Pattern**: Changes to `/apps/`, `/databases/`, and `/infrastructure/` are automatically deployed by ArgoCD
- **Secrets Management**: All secrets are stored in Azure Key Vault and synced via External Secrets Operator
- **Backup Strategy**: Database backups are automated and stored in Azure Blob Storage
- **Resource Dependencies**: Shared environment must be deployed before other environments
- **State Management**: Terraform state is managed locally (consider remote state for production)
