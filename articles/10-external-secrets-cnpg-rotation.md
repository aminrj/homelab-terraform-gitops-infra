# External Secrets + CNPG: Automatic Database Credential Management and Rotation

*Complete guide to integrating Azure Key Vault with Kubernetes using External Secrets Operator, eliminating hardcoded credentials and enabling automatic rotation for CNPG databases.*

## The Problem with Kubernetes Secrets

Traditional Kubernetes secrets are base64-encoded values stored in Git or applied with kubectl:

```yaml
# DON'T DO THIS - Secrets in Git
apiVersion: v1
kind: Secret
metadata:
  name: n8n-db-creds
type: Opaque
data:
  username: bjhu  # base64("n8n")
  password: c3VwZXJzZWNyZXRwYXNzd29yZA==  # base64("supersecretpassword")
```

**Problems:**
- Secrets committed to Git (security risk)
- No centralized secret management
- Manual rotation process
- Secrets visible in kubectl output
- No audit trail

## The Solution: External Secrets Operator

External Secrets Operator (ESO) syncs secrets from external secret managers (Azure Key Vault, AWS Secrets Manager, HashiCorp Vault, etc.) into Kubernetes Secrets automatically.

**Benefits:**
- Secrets never in Git
- Centralized in Azure Key Vault
- Automatic synchronization
- Rotation support
- Audit logging in Azure
- RBAC integration

## Architecture

```
┌──────────────────────────────────────────────┐
│  Terraform                                   │
│  ├─ Creates Azure Key Vault                  │
│  ├─ Generates database credentials           │
│  ├─ Stores in Key Vault                      │
│  └─ Deploys External Secrets Operator        │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│  External Secrets Operator (in Kubernetes)   │
│  ├─ ClusterSecretStore (Azure KV connection) │
│  └─ Watches ExternalSecret resources         │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│  ExternalSecret (defined in Git)             │
│  ├─ References ClusterSecretStore            │
│  ├─ Maps Azure KV secrets to K8s secrets     │
│  └─ Refreshes every 1 hour                   │
└──────────────┬───────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────┐
│  Kubernetes Secret (auto-created)            │
│  ├─ Created by ESO                           │
│  ├─ Used by CNPG clusters                    │
│  └─ Used by applications                     │
└──────────────────────────────────────────────┘
```

## Setup: Terraform → Azure Key Vault

### Step 1: Create Azure Key Vault

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

  tags = {
    environment = "prod"
    managed-by  = "terraform"
  }
}

# Grant Terraform access to create secrets
resource "azurerm_role_assignment" "keyvault_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

### Step 2: Generate and Store Database Credentials

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

Usage in environment:

```hcl
# environments/prod/main.tf
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
}
```

This creates secrets in Azure Key Vault:
- `n8n-db-username` = "n8n"
- `n8n-db-name` = "n8n"
- `n8n-db-password` = (32-char random string)
- `n8n-encryption-key` = (32-char random string)

### Step 3: Create Service Principal for ESO

```bash
# Create service principal for External Secrets Operator
az ad sp create-for-rbac \
  --name "external-secrets-homelab-prod" \
  --role "Key Vault Secrets User" \
  --scopes /subscriptions/<sub-id>/resourceGroups/homelab-prod-rg

# Output:
# {
#   "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#   "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
#   "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# }

# Store these credentials - you'll need them for ClusterSecretStore
```

Grant Key Vault access:

```bash
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee <appId-from-above> \
  --scope /subscriptions/<sub-id>/resourceGroups/homelab-prod-rg/providers/Microsoft.KeyVault/vaults/homelab-keyvault-prod
```

## Setup: External Secrets Operator

### Step 4: Install ESO with Terraform

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

      processClusterStore          = true
      processClusterExternalSecret = true

      rbac = {
        create      = true
        clusterWide = true
      }

      serviceAccount = {
        create = true
        name   = "external-secrets-sa"
      }
    })
  ]
}
```

### Step 5: Create Bootstrap Secret

```bash
# Create secret with Azure credentials
kubectl create secret generic azure-creds \
  -n external-secrets \
  --from-literal=client-id="<appId>" \
  --from-literal=client-secret="<password>"
```

Or with Terraform:

```hcl
resource "kubernetes_secret" "azure_credentials" {
  metadata {
    name      = "azure-creds"
    namespace = "external-secrets"
  }

  data = {
    client-id     = var.azure_client_id
    client-secret = var.azure_client_secret
  }

  depends_on = [module.external_secrets]
}
```

### Step 6: Create ClusterSecretStore

```yaml
# infrastructure/external-secrets/overlays/prod/clustersecretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-kv-store-prod
spec:
  provider:
    azurekv:
      authType: ServicePrincipal
      vaultUrl: https://homelab-keyvault-prod.vault.azure.net/
      tenantId: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      authSecretRef:
        clientId:
          name: azure-creds
          namespace: external-secrets
          key: client-id
        clientSecret:
          name: azure-creds
          namespace: external-secrets
          key: client-secret
```

Apply:

```bash
kubectl apply -f infrastructure/external-secrets/overlays/prod/clustersecretstore.yaml
```

Verify:

```bash
$ kubectl get clustersecretstore
NAME                   AGE   STATUS   READY
azure-kv-store-prod    5m    Valid    True
```

## Using External Secrets with CNPG

### Database Cluster Configuration

```yaml
# databases/n8n/base/cluster.yaml (excerpt)
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: n8n-db-cnpg-v3
spec:
  instances: 2

  bootstrap:
    initdb:
      database: n8n
      owner: n8n
      secret:
        name: n8n-db-creds  # Created by ExternalSecret

  backup:
    barmanObjectStore:
      destinationPath: # From ExternalSecret
      azureCredentials:
        storageAccount:
          name: n8n-db-storage  # Created by ExternalSecret
          key: container-name
        storageSasToken:
          name: n8n-db-storage
          key: blob-sas
```

### ExternalSecret for Database Credentials

```yaml
# databases/n8n/overlays/prod/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-db-creds
  namespace: cnpg-prod
spec:
  refreshInterval: 1h  # Sync from Azure every hour
  secretStoreRef:
    name: azure-kv-store-prod
    kind: ClusterSecretStore
  target:
    name: n8n-db-creds
    creationPolicy: Owner  # ESO creates and owns the secret
  data:
    - secretKey: username
      remoteRef:
        key: n8n-db-username
    - secretKey: password
      remoteRef:
        key: n8n-db-password
```

This creates a Kubernetes secret:

```yaml
# Auto-created by ESO (do not manually create)
apiVersion: v1
kind: Secret
metadata:
  name: n8n-db-creds
  namespace: cnpg-prod
type: Opaque
data:
  username: bjhu           # Synced from Azure
  password: <32-char-pwd>  # Synced from Azure
```

### ExternalSecret for Backup Storage

```yaml
# databases/n8n/overlays/prod/secrets.yaml
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-db-storage
  namespace: cnpg-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-kv-store-prod
    kind: ClusterSecretStore
  target:
    name: n8n-db-storage
    creationPolicy: Owner
  data:
    - secretKey: blob-sas
      remoteRef:
        key: n8n-db-blob-sas
    - secretKey: container-name
      remoteRef:
        key: n8n-db-container-name
    - secretKey: destination-path
      remoteRef:
        key: n8n-db-destination-path
```

## Using External Secrets with Applications

### Application Database Connection

```yaml
# apps/n8n/overlays/prod/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-db-creds
  namespace: n8n-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-kv-store-prod
    kind: ClusterSecretStore
  target:
    name: n8n-db-creds
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: n8n-db-username
    - secretKey: password
      remoteRef:
        key: n8n-db-password

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-encryption
  namespace: n8n-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-kv-store-prod
    kind: ClusterSecretStore
  target:
    name: n8n-encryption
    creationPolicy: Owner
  data:
    - secretKey: key
      remoteRef:
        key: n8n-encryption-key
```

### Application Deployment

```yaml
# apps/n8n/base/deployment.yaml (excerpt)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
spec:
  template:
    spec:
      containers:
      - name: n8n
        env:
        - name: DB_POSTGRESDB_USER
          valueFrom:
            secretKeyRef:
              name: n8n-db-creds  # Created by ExternalSecret
              key: username
        - name: DB_POSTGRESDB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: n8n-db-creds
              key: password
        - name: N8N_ENCRYPTION_KEY
          valueFrom:
            secretKeyRef:
              name: n8n-encryption
              key: key
```

## Complete Example: Adding a New Application

### 1. Add Secrets to Azure Key Vault (Terraform)

```hcl
# environments/prod/main.tf
module "newapp_secrets" {
  source       = "../../modules/azure-secrets"
  key_vault_id = module.azure_keyvault.key_vault_id
  app_name     = "newapp"

  static_secrets = {
    "db-username" = "newapp"
    "db-name"     = "newapp"
  }

  random_secrets = [
    "db-password",
    "api-key"
  ]
}
```

```bash
terraform apply
```

This creates in Azure Key Vault:
- `newapp-db-username`
- `newapp-db-name`
- `newapp-db-password`
- `newapp-api-key`

### 2. Create ExternalSecrets (ArgoCD/Git)

```yaml
# databases/newapp/overlays/prod/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: newapp-db-creds
  namespace: cnpg-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-kv-store-prod
    kind: ClusterSecretStore
  target:
    name: newapp-db-creds
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: newapp-db-username
    - secretKey: password
      remoteRef:
        key: newapp-db-password
```

```yaml
# apps/newapp/overlays/prod/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: newapp-creds
  namespace: newapp-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-kv-store-prod
    kind: ClusterSecretStore
  target:
    name: newapp-creds
    creationPolicy: Owner
  data:
    - secretKey: db-username
      remoteRef:
        key: newapp-db-username
    - secretKey: db-password
      remoteRef:
        key: newapp-db-password
    - secretKey: api-key
      remoteRef:
        key: newapp-api-key
```

### 3. Commit and Push

```bash
git add databases/newapp apps/newapp
git commit -m "Add newapp with External Secrets"
git push
```

ArgoCD automatically:
1. Creates ExternalSecret resources
2. ESO syncs secrets from Azure Key Vault
3. Kubernetes Secrets created automatically
4. CNPG cluster uses secrets for database
5. Application uses secrets for config

## Credential Rotation

### Manual Rotation

```bash
# Update secret in Azure Key Vault
az keyvault secret set \
  --vault-name homelab-keyvault-prod \
  --name n8n-db-password \
  --value "new-password-here"

# ESO will sync within refreshInterval (1 hour)
# Or force immediate sync
kubectl annotate externalsecret n8n-db-creds \
  -n cnpg-prod \
  force-sync=$(date +%s)
```

### Automatic Rotation with Azure

```hcl
# modules/azure-secrets/main.tf
resource "azurerm_key_vault_secret" "random" {
  for_each = toset(var.random_secrets)

  name         = "${var.app_name}-${each.key}"
  value        = random_password.passwords[each.key].result
  key_vault_id = var.key_vault_id

  # Set expiration
  expiration_date = timeadd(timestamp(), "2160h")  # 90 days

  lifecycle {
    ignore_changes = [expiration_date]
  }
}
```

Set up rotation policy:

```bash
az keyvault secret set-attributes \
  --vault-name homelab-keyvault-prod \
  --name n8n-db-password \
  --expires "$(date -u -d '+90 days' '+%Y-%m-%dT%H:%M:%SZ')"
```

### Application Restart After Rotation

For applications to pick up new passwords, they need to restart:

```bash
# Restart deployment to use new secret
kubectl rollout restart deployment/n8n -n n8n-prod
```

Or use Reloader for automatic restarts:

```bash
helm install reloader stakater/reloader -n kube-system

# Add annotation to deployments
metadata:
  annotations:
    secret.reloader.stakater.com/reload: "n8n-db-creds,n8n-encryption"
```

## Monitoring and Troubleshooting

### Check ExternalSecret Status

```bash
$ kubectl get externalsecrets -A
NAMESPACE    NAME              STORE                  REFRESH   STATUS
cnpg-prod    n8n-db-creds      azure-kv-store-prod    1h        SecretSynced
cnpg-prod    n8n-db-storage    azure-kv-store-prod    1h        SecretSynced
n8n-prod     n8n-db-creds      azure-kv-store-prod    1h        SecretSynced
n8n-prod     n8n-encryption    azure-kv-store-prod    1h        SecretSynced
```

```bash
$ kubectl describe externalsecret n8n-db-creds -n cnpg-prod
Status:
  Conditions:
    Status:  True
    Type:    Ready
  Refresh Time:  2024-10-05T12:00:00Z
  Synced Resource Version:  1.2.3
```

### Common Issues

**Issue: Status shows "SecretSyncedError"**

```bash
kubectl describe externalsecret n8n-db-creds -n cnpg-prod
# Check error message

# Common causes:
# 1. Secret doesn't exist in Azure Key Vault
# 2. Service principal lacks permissions
# 3. Wrong secret name
```

**Fix:**

```bash
# Verify secret exists
az keyvault secret show \
  --vault-name homelab-keyvault-prod \
  --name n8n-db-password

# Check permissions
az role assignment list \
  --assignee <service-principal-id> \
  --scope /subscriptions/<sub-id>/resourceGroups/homelab-prod-rg/providers/Microsoft.KeyVault/vaults/homelab-keyvault-prod
```

**Issue: Secret not syncing**

```bash
# Check ESO controller logs
kubectl logs -n external-secrets deployment/external-secrets -f

# Force sync
kubectl annotate externalsecret n8n-db-creds \
  -n cnpg-prod \
  force-sync=$(date +%s) \
  --overwrite
```

## Security Best Practices

### 1. Use ClusterSecretStore (Not SecretStore)

```yaml
# GOOD - ClusterSecretStore (one config for entire cluster)
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-kv-store-prod

# AVOID - SecretStore (per-namespace, duplicated config)
```

### 2. Least Privilege for Service Principal

```bash
# Only grant "Key Vault Secrets User" (read-only)
# Don't grant "Key Vault Administrator"
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee <sp-id> \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>
```

### 3. Separate Service Principals Per Environment

```bash
# Prod SP can only access prod Key Vault
az ad sp create-for-rbac --name "external-secrets-prod"

# QA SP can only access QA Key Vault
az ad sp create-for-rbac --name "external-secrets-qa"
```

### 4. Use RBAC in Azure Key Vault

```hcl
resource "azurerm_key_vault" "main" {
  enable_rbac_authorization = true  # Use RBAC instead of access policies
}
```

### 5. Audit Secret Access

```bash
# Enable diagnostic logs
az monitor diagnostic-settings create \
  --resource /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/homelab-keyvault-prod \
  --name audit-logs \
  --logs '[{"category": "AuditEvent","enabled": true}]' \
  --workspace /subscriptions/<sub>/resourceGroups/<rg>/providers/microsoft.operationalinsights/workspaces/<workspace>
```

## Conclusion

External Secrets Operator eliminates hardcoded credentials:

**Benefits:**
- No secrets in Git
- Centralized secret management
- Automatic synchronization
- Rotation support
- Audit logging

**Setup Summary:**
1. Terraform creates Azure Key Vault
2. Terraform generates and stores secrets
3. Terraform deploys ESO
4. Create ClusterSecretStore
5. Define ExternalSecrets in Git
6. ESO syncs automatically

**For CNPG:**
- Database credentials from Azure KV
- Backup storage credentials from Azure KV
- No manual secret creation
- Automatic rotation supported

This is production-grade secret management for Kubernetes.

---

**Related Reading:**
- [Terraform + ArgoCD GitOps Stack](#) - Infrastructure setup
- [CNPG Backup and Restore Patterns](#) - Using secrets for backups
- [CNPG Multi-Environment Strategy](#) - Per-environment secrets

**Code Repository:** [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
