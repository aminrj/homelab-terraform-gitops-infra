# Gitea Azure Key Vault Secrets

## Overview

When you run `terraform apply`, the following secrets will be automatically created in your Azure Key Vault.

## Secrets Created by Terraform

### Application Secrets (via `gitea_secrets` module)

| Secret Name | Type | Description | Usage |
|-------------|------|-------------|-------|
| `gitea-db-username` | Static | Database username: `gitea` | PostgreSQL authentication |
| `gitea-db-name` | Static | Database name: `gitea` | PostgreSQL database name |
| `gitea-db-password` | Random (32 chars) | Database password | PostgreSQL authentication |
| `gitea-secret-key` | Random (32 chars) | Gitea SECRET_KEY | Session encryption |
| `gitea-internal-token` | Random (32 chars) | Gitea INTERNAL_TOKEN | API authentication |

### Storage Secrets (via `app_storage["gitea"]` module)

| Secret Name | Type | Description | Usage |
|-------------|------|-------------|-------|
| `gitea-db-clean-blob-sas` | Generated SAS | Azure Blob SAS token | Database backup access |
| `gitea-db-clean-container-name` | Static | Container name: `gitea-db-clean` | Backup destination |
| `gitea-db-clean-destination-path` | Generated | Full Azure Blob URL | CNPG backup path |

## How Secrets are Used

### 1. Application Pod (`apps/gitea/overlays/prod/secrets.yaml`)

ExternalSecret `gitea-db-creds` pulls:
- `gitea-db-username` → `username`
- `gitea-db-password` → `password`
- `gitea-db-name` → `database`

ExternalSecret `gitea-secrets` pulls:
- `gitea-secret-key` → `secret-key`
- `gitea-internal-token` → `internal-token`

### 2. Database Pod (`databases/gitea/overlays/prod/secrets.yaml`)

ExternalSecret `gitea-db-creds` pulls:
- `gitea-db-username` → `username`
- `gitea-db-password` → `password`
- `gitea-db-name` → `database`

ExternalSecret `gitea-db-storage` pulls:
- `gitea-db-clean-container-name` → `container-name`
- `gitea-db-clean-blob-sas` → `blob-sas`

## Terraform Configuration

### Module: `gitea_secrets`

```terraform
module "gitea_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "gitea"

  static_secrets = {
    "db-username" = "gitea"
    "db-name"     = "gitea"
  }

  random_secrets = [
    "db-password",
    "secret-key",
    "internal-token"
  ]

  depends_on = [
    module.azure_keyvault
  ]
}
```

### Module: `app_storage["gitea"]`

```terraform
locals {
  apps = {
    # ... other apps ...
    gitea = { container_name = "gitea-db-clean" }
  }
}

module "app_storage" {
  for_each             = local.apps
  source               = "../../modules/azure-app-storage"
  container_name       = each.value.container_name
  storage_account_name = module.azure_keyvault.storage_account_name
  resource_group_name  = azurerm_resource_group.main.name
  connection_string    = module.azure_keyvault.storage_connection_string
  key_vault_id         = module.azure_keyvault.key_vault_id
}
```

## Verification

After `terraform apply`, verify secrets exist in Azure Key Vault:

```bash
# List all Gitea secrets
az keyvault secret list \
  --vault-name <your-keyvault-name> \
  --query "[?contains(name, 'gitea')].name" \
  -o table

# View a specific secret (be careful with sensitive data!)
az keyvault secret show \
  --vault-name <your-keyvault-name> \
  --name gitea-db-username \
  --query "value" \
  -o tsv
```

Or check in Kubernetes:

```bash
# Check if ExternalSecrets are synced
kubectl get externalsecrets -n gitea-prod
kubectl get externalsecrets -n cnpg-prod | grep gitea

# Check if Kubernetes secrets are created
kubectl get secrets -n gitea-prod | grep gitea
kubectl get secrets -n cnpg-prod | grep gitea

# Describe an ExternalSecret to see sync status
kubectl describe externalsecret gitea-db-creds -n gitea-prod
```

## Security Notes

1. **Random Passwords**: All passwords and tokens are 32-character cryptographically random strings
2. **SAS Token**: Azure Blob SAS token expires after 1 year (8760 hours) and needs rotation
3. **Lifecycle Management**: Terraform uses `ignore_changes = [value]` to prevent overwriting manually updated secrets
4. **Access Control**: Only the External Secrets Operator service principal can read from Key Vault

## Troubleshooting

### ExternalSecret not syncing

```bash
# Check External Secrets Operator logs
kubectl logs -n external-secrets-system deploy/external-secrets -f

# Check ClusterSecretStore
kubectl get clustersecretstore azure-kv-store-prod -o yaml

# Check ExternalSecret status
kubectl get externalsecret gitea-db-creds -n gitea-prod -o yaml
```

### Missing secrets in Key Vault

```bash
# Re-run Terraform plan to see what's missing
cd environments/prod
terraform plan -var-file="terraform.tfvars"

# Apply to create missing secrets
terraform apply -var-file="terraform.tfvars"
```

### Database backup failing

Check if storage secrets are correct:

```bash
# Check the backup configuration
kubectl get backup -n cnpg-prod -l cnpg.io/cluster=gitea-db-cnpg-v1

# Check backup logs
kubectl logs -n cnpg-prod gitea-db-cnpg-v1-1 | grep -i backup

# Verify storage secrets
kubectl get secret gitea-db-storage -n cnpg-prod -o yaml
```

## Integration with Gitea

Gitea uses these environment variables (from `apps/gitea/base/deployment.yaml`):

```yaml
env:
  - name: GITEA__database__DB_TYPE
    value: "postgres"
  - name: GITEA__database__HOST
    value: "gitea-db-cnpg-v1-rw.cnpg-prod.svc.cluster.local:5432"
  - name: GITEA__database__NAME
    valueFrom:
      secretKeyRef:
        name: gitea-db-creds
        key: database
  - name: GITEA__database__USER
    valueFrom:
      secretKeyRef:
        name: gitea-db-creds
        key: username
  - name: GITEA__database__PASSWD
    valueFrom:
      secretKeyRef:
        name: gitea-db-creds
        key: password
  - name: GITEA__security__SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: gitea-secrets
        key: secret-key
  - name: GITEA__security__INTERNAL_TOKEN
    valueFrom:
      secretKeyRef:
        name: gitea-secrets
        key: internal-token
```

---

**Summary**: All secrets are automatically managed by Terraform. When you run `terraform apply`, 8 secrets will be created in Azure Key Vault. The External Secrets Operator will sync them to Kubernetes secrets that Gitea and PostgreSQL will use.
