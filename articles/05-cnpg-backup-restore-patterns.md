# CNPG Backup and Restore Patterns: From Azure to Point-in-Time Recovery

*Complete guide to CloudNativePG backup strategies, from automated scheduled backups to Azure storage, cross-environment restores, and disaster recovery testing.*

## Why Backups Matter (A Personal Story)

Backups are insurance. You don't think about them until you need them. But when you need them, they're everything.

I recently had to restore my n8n database from backups after a migration issue. The process took 5 minutes because I had:
1. Automated daily backups to Azure Blob Storage
2. Tested the restore procedure
3. Documented the exact commands

Without backups, I would have lost all my automation workflows, credentials, and execution history. With backups, it was a non-event.

Let me show you the exact setup I use.

## The Backup Architecture

My backup strategy has three layers:

1. **Continuous WAL archiving** - Every transaction is backed up to Azure
2. **Scheduled full backups** - Daily snapshots to Azure Blob Storage
3. **Cross-environment backup copies** - Prod backups accessible from QA/dev

```
PostgreSQL Cluster (CNPG)
    ├── WAL Archive → Azure Blob (continuous)
    ├── Full Backup → Azure Blob (daily at 2 AM)
    └── Retention → 7 days

Azure Storage Account
    ├── n8n-prod-backups/
    │   ├── base/               # Full backups
    │   └── wals/               # WAL segments
    ├── commafeed-prod-backups/
    ├── linkding-prod-backups/
    └── ... etc
```

## Setting Up Azure Blob Storage

### Step 1: Create Azure Storage Account

```bash
# Via Azure CLI
az storage account create \
  --name homelabstorageaccntprod \
  --resource-group homelab-rg \
  --location eastus \
  --sku Standard_LRS \
  --kind StorageV2

# Create containers for each app/environment
az storage container create \
  --name n8n-prod-backups \
  --account-name homelabstorageaccntprod

az storage container create \
  --name n8n-qa-backups \
  --account-name homelabstorageaccntprod
```

### Step 2: Generate SAS Token

```bash
# Generate SAS token with read/write permissions
az storage container generate-sas \
  --name n8n-prod-backups \
  --account-name homelabstorageaccntprod \
  --permissions rwdl \
  --expiry 2025-12-31T23:59:59Z \
  --output tsv

# Save this token - you'll need it for Kubernetes secrets
```

### Step 3: Store Credentials in Azure Key Vault

```bash
# Store storage account name
az keyvault secret set \
  --vault-name homelab-keyvault \
  --name n8n-db-storage-account \
  --value "homelabstorageaccntprod"

# Store container name
az keyvault secret set \
  --vault-name homelab-keyvault \
  --name n8n-db-container-name \
  --value "n8n-prod-backups"

# Store SAS token
az keyvault secret set \
  --vault-name homelab-keyvault \
  --name n8n-db-blob-sas \
  --value "sp=rwdl&st=2024..."
```

## Configuring CNPG Backups

### Base Cluster Configuration

```yaml
# databases/n8n/base/cluster.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: n8n-db-cnpg-v3
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  instances: 2

  storage:
    size: 20Gi

  # Backup configuration
  backup:
    barmanObjectStore:
      destinationPath: # Set in overlay
      azureCredentials:
        storageAccount:
          name: n8n-db-storage
          key: container-name
        storageSasToken:
          name: n8n-db-storage
          key: blob-sas
      wal:
        compression: gzip
        maxParallel: 2
      data:
        compression: gzip
        jobs: 2  # Parallel backup jobs
    retentionPolicy: 7d  # Keep 7 days of backups

  # Point-in-time recovery
  enablePITR: true  # Enables WAL archiving
```

**Key settings explained:**

- `barmanObjectStore` - Uses Barman (backup manager) with object storage
- `destinationPath` - Azure Blob Storage URL (set in overlay)
- `wal.compression` - Compress WAL files to save storage
- `retentionPolicy: 7d` - Keep backups for 7 days
- `enablePITR: true` - Enable point-in-time recovery via WAL archiving

### Production Overlay

```yaml
# databases/n8n/overlays/prod/kustomization.yaml
namespace: cnpg-prod

resources:
  - ../../base
  - scheduled-backup.yaml
  - secrets.yaml

patches:
  - path: destination-path-patch.yaml
```

```yaml
# databases/n8n/overlays/prod/destination-path-patch.yaml
- op: replace
  path: /spec/backup/barmanObjectStore/destinationPath
  value: https://homelabstorageaccntprod.blob.core.windows.net/n8n-prod-backups
```

```yaml
# databases/n8n/overlays/prod/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-db-storage
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault-prod
    kind: SecretStore
  target:
    name: n8n-db-storage
    creationPolicy: Owner
  data:
    - secretKey: container-name
      remoteRef:
        key: n8n-db-container-name
    - secretKey: blob-sas
      remoteRef:
        key: n8n-db-blob-sas
```

```yaml
# databases/n8n/overlays/prod/scheduled-backup.yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: n8n-daily-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM UTC
  backupOwnerReference: cluster
  cluster:
    name: n8n-db-cnpg-v3
  suspend: false
```

Apply the configuration:

```bash
kubectl apply -k databases/n8n/overlays/prod/

# Verify backup configuration
kubectl get cluster n8n-db-cnpg-v3 -n cnpg-prod -o yaml | grep -A 10 backup
```

## Monitoring Backups

### Check Backup Status

```bash
# List all backups
kubectl get backups -n cnpg-prod
NAME                               AGE   CLUSTER          PHASE       ERROR
n8n-db-cnpg-v3-20241004020000      1d    n8n-db-cnpg-v3   completed
n8n-db-cnpg-v3-20241003020000      2d    n8n-db-cnpg-v3   completed
n8n-db-cnpg-v3-20241002020000      3d    n8n-db-cnpg-v3   completed

# Check specific backup details
kubectl describe backup n8n-db-cnpg-v3-20241004020000 -n cnpg-prod

# Check scheduled backup status
kubectl get scheduledbackups -n cnpg-prod
NAME                AGE   CLUSTER          LAST BACKUP               LAST BACKUP AGE
n8n-daily-backup    15d   n8n-db-cnpg-v3   2024-10-04T02:00:00Z      5h
```

### Check Cluster Backup Status

```bash
kubectl cnpg status n8n-db-cnpg-v3 -n cnpg-prod

# Output includes backup info:
# Cluster Summary
# Name:                   n8n-db-cnpg-v3
# ...
# Continuous Backup status
# First Point of Recoverability:  2024-09-27 02:05:14 +0000 UTC
# Last Successful Backup:          2024-10-04 02:00:32 +0000 UTC
# ...
```

### Verify Backups in Azure

```bash
# List backups in Azure Blob Storage
az storage blob list \
  --container-name n8n-prod-backups \
  --account-name homelabstorageaccntprod \
  --output table

# Check backup sizes
az storage blob list \
  --container-name n8n-prod-backups \
  --account-name homelabstorageaccntprod \
  --query "[].{Name:name, Size:properties.contentLength}" \
  --output table
```

## Restoring From Backup

### Scenario 1: Full Cluster Restore (Disaster Recovery)

You need to recreate the entire cluster from a backup.

**Step 1:** Create restore configuration

```yaml
# databases/n8n/overlays/prod/restore-from-backup.yaml
- op: replace
  path: /spec/bootstrap
  value:
    recovery:
      source: clusterBackup

- op: add
  path: /spec/externalClusters
  value:
    - name: clusterBackup
      barmanObjectStore:
        destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/n8n-prod-backups
        azureCredentials:
          storageAccount:
            name: n8n-db-storage
            key: container-name
          storageSasToken:
            name: n8n-db-storage
            key: blob-sas
        wal:
          compression: gzip
```

**Step 2:** Update kustomization to include restore patch

```yaml
# databases/n8n/overlays/prod/kustomization.yaml
namespace: cnpg-prod

resources:
  - ../../base
  - scheduled-backup.yaml
  - secrets.yaml

patches:
  - path: destination-path-patch.yaml
  - path: restore-from-backup.yaml  # Add this
```

**Step 3:** Delete old cluster and recreate from backup

```bash
# DANGER: This deletes the database cluster
kubectl delete cluster n8n-db-cnpg-v3 -n cnpg-prod

# Wait for deletion
kubectl wait --for=delete cluster/n8n-db-cnpg-v3 -n cnpg-prod --timeout=300s

# Create new cluster with recovery
kubectl apply -k databases/n8n/overlays/prod/

# Watch recovery progress
kubectl get cluster n8n-db-cnpg-v3 -n cnpg-prod -w
# Status will show: "Cluster is being restored"
# Then: "Cluster in healthy state"

# Check logs
kubectl logs -n cnpg-prod n8n-db-cnpg-v3-1 -f
```

**Step 4:** Verify data integrity

```bash
# Connect to database
kubectl exec -it n8n-db-cnpg-v3-1 -n cnpg-prod -- psql -U postgres

postgres=# \c n8n
n8n=# SELECT COUNT(*) FROM workflow;
 count
-------
   42
(1 row)

n8n=# \q
```

**Step 5:** Remove restore patch for next deployment

```yaml
# databases/n8n/overlays/prod/kustomization.yaml
# Comment out restore patch after successful restore
patches:
  - path: destination-path-patch.yaml
  # - path: restore-from-backup.yaml  # Commented out
```

### Scenario 2: Point-in-Time Recovery

Restore to a specific point in time (requires WAL archiving enabled).

```yaml
# databases/n8n/overlays/prod/restore-pitr.yaml
- op: replace
  path: /spec/bootstrap
  value:
    recovery:
      source: clusterBackup
      recoveryTarget:
        targetTime: "2024-10-04 14:30:00.000000+00"  # Specific timestamp

- op: add
  path: /spec/externalClusters
  value:
    - name: clusterBackup
      barmanObjectStore:
        destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/n8n-prod-backups
        azureCredentials:
          storageAccount:
            name: n8n-db-storage
            key: container-name
          storageSasToken:
            name: n8n-db-storage
            key: blob-sas
```

**Use case:** "I accidentally deleted all workflows at 2:45 PM. Restore to 2:30 PM."

### Scenario 3: Cross-Environment Restore (Prod to QA)

Copy production data to QA for testing.

```yaml
# databases/n8n/overlays/qa/restore-from-prod.yaml
- op: replace
  path: /spec/bootstrap
  value:
    recovery:
      source: prodCluster

- op: add
  path: /spec/externalClusters
  value:
    - name: prodCluster
      barmanObjectStore:
        destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/n8n-prod-backups
        # ^ Points to PROD backups
        azureCredentials:
          storageAccount:
            name: n8n-db-storage
            key: container-name
          storageSasToken:
            name: n8n-db-storage
            key: blob-sas
```

```bash
# Delete QA cluster
kubectl delete cluster n8n-db-cnpg-v3 -n cnpg-qa

# Recreate with prod data
kubectl apply -k databases/n8n/overlays/qa/

# QA now has copy of production data for testing
```

### Scenario 4: Single Database Restore

Restore just one database within a cluster.

```bash
# Connect to cluster
kubectl exec -it n8n-db-cnpg-v3-1 -n cnpg-prod -- bash

# Inside the pod:
# Create new database for restore
createdb -U postgres n8n_restored

# Restore from backup
barman-cloud-restore \
  --endpoint-url https://homelabstorageaccntprod.blob.core.windows.net \
  n8n-prod-backups \
  20241004020000 \
  /tmp/restore

# Import to new database
pg_restore -d n8n_restored -U postgres /tmp/restore

# Verify
psql -U postgres -d n8n_restored -c "SELECT COUNT(*) FROM workflow;"
```

## Testing Backup Restores

**Critical:** Untested backups are worthless. Test quarterly.

### Monthly Restore Test Procedure

```bash
#!/bin/bash
# test-restore.sh - Monthly backup restore test

set -euo pipefail

APP="n8n"
TIMESTAMP=$(date +%Y%m%d)

echo "==> Testing restore for $APP on $TIMESTAMP"

# Create test namespace
kubectl create namespace backup-test-${TIMESTAMP}

# Create temporary cluster from backup
cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${APP}-restore-test
  namespace: backup-test-${TIMESTAMP}
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  instances: 1
  storage:
    size: 10Gi

  bootstrap:
    recovery:
      source: prodBackup

  externalClusters:
    - name: prodBackup
      barmanObjectStore:
        destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/${APP}-prod-backups
        azureCredentials:
          storageAccount:
            name: ${APP}-db-storage
            key: container-name
          storageSasToken:
            name: ${APP}-db-storage
            key: blob-sas
EOF

# Wait for restore
echo "Waiting for restore to complete..."
kubectl wait --for=jsonpath='{.status.phase}'='Cluster in healthy state' \
  cluster/${APP}-restore-test \
  -n backup-test-${TIMESTAMP} \
  --timeout=600s

# Verify data
echo "Verifying data integrity..."
WORKFLOW_COUNT=$(kubectl exec -it ${APP}-restore-test-1 -n backup-test-${TIMESTAMP} -- \
  psql -U postgres -d n8n -tAc "SELECT COUNT(*) FROM workflow")

echo "Workflow count: $WORKFLOW_COUNT"

if [ "$WORKFLOW_COUNT" -gt 0 ]; then
  echo "✅ Restore test PASSED"
else
  echo "❌ Restore test FAILED"
  exit 1
fi

# Cleanup
kubectl delete namespace backup-test-${TIMESTAMP}

echo "==> Test complete"
```

Run monthly:

```bash
chmod +x test-restore.sh
./test-restore.sh

# Or add to cron
0 2 1 * * /path/to/test-restore.sh | mail -s "Backup Test Results" admin@example.com
```

## Backup Best Practices

### 1. Monitor Backup Age

```yaml
# Prometheus alert for stale backups
- alert: BackupTooOld
  expr: |
    (time() - cnpg_backup_last_successful_timestamp) > 86400
  for: 1h
  annotations:
    summary: "No successful backup in 24h for {{ $labels.cluster }}"
```

### 2. Verify Backup Sizes

```bash
# Backups should be roughly consistent in size
# Sudden size changes indicate problems

kubectl get backups -n cnpg-prod -o json | \
  jq -r '.items[] | "\(.metadata.name) \(.status.size)"'
```

### 3. Encrypt Backups (Optional)

```yaml
# Add encryption to backup configuration
backup:
  barmanObjectStore:
    serverName: n8n-db-cnpg-v3
    encryption: AES256
    # Azure handles encryption at rest by default
```

### 4. Test Cross-Region Restore

```bash
# Copy backups to different Azure region
az storage blob copy start-batch \
  --source-container n8n-prod-backups \
  --account-name homelabstorageaccntprod \
  --destination-container n8n-prod-backups-dr \
  --account-name homelabstoragecdr  # Different region
```

### 5. Document Recovery Procedures

```markdown
# DISASTER_RECOVERY.md

## N8N Database Recovery

**RTO:** 30 minutes
**RPO:** 24 hours (daily backups)

### Steps:
1. Verify backups exist in Azure: `az storage blob list...`
2. Apply restore patch: `kubectl apply -k databases/n8n/overlays/prod/`
3. Wait for recovery: `kubectl get cluster -w`
4. Test application: Access n8n UI and verify workflows
5. Remove restore patch from kustomization

### Contacts:
- DBA: John Doe (john@example.com)
- Azure Access: Jane Smith (jane@example.com)
```

## Cost Optimization

Azure Blob Storage costs money. Optimize retention and storage tiers.

### Storage Tier Strategy

```bash
# Move old backups to cool tier
az storage blob set-tier \
  --container-name n8n-prod-backups \
  --name base/20241001T020000/data.tar.gz \
  --tier Cool

# Or use lifecycle policies
az storage account management-policy create \
  --account-name homelabstorageaccntprod \
  --policy @lifecycle-policy.json
```

```json
{
  "rules": [
    {
      "name": "moveOldBackupsToCool",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["n8n-prod-backups/base"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 7
            },
            "delete": {
              "daysAfterModificationGreaterThan": 30
            }
          }
        }
      }
    }
  ]
}
```

**Estimated costs (monthly):**
- 50GB backups in Hot tier: ~$1
- 50GB backups in Cool tier: ~$0.50
- 50GB in Archive tier: ~$0.10

## Troubleshooting

### Backup Fails: "Permission Denied"

**Cause:** SAS token expired or wrong permissions

**Fix:**
```bash
# Generate new SAS token
az storage container generate-sas \
  --name n8n-prod-backups \
  --account-name homelabstorageaccntprod \
  --permissions rwdl \
  --expiry 2026-12-31

# Update in Key Vault
az keyvault secret set \
  --vault-name homelab-keyvault \
  --name n8n-db-blob-sas \
  --value "NEW_SAS_TOKEN"

# External Secrets will sync automatically
```

### Restore Hangs at "Cluster is being restored"

**Cause:** WAL files missing or corrupted

**Debug:**
```bash
# Check cluster events
kubectl describe cluster n8n-db-cnpg-v3 -n cnpg-prod

# Check pod logs
kubectl logs -n cnpg-prod n8n-db-cnpg-v3-1 --tail=100

# Look for WAL errors:
# "could not restore file 000000010000000000000042"

# Solution: Restore from earlier backup
```

### Out of Space During Restore

**Cause:** PVC too small for backup data

**Fix:**
```yaml
# Increase storage size
spec:
  storage:
    size: 30Gi  # Increased from 20Gi
```

## Conclusion

Backups are not optional. With CNPG and Azure Blob Storage:

**What you get:**
- Automated daily backups
- Point-in-time recovery
- Cross-environment data copying
- 7-day retention
- Tested recovery procedures

**What it costs:**
- ~$1-2/month in Azure storage
- 30 minutes setup time per app
- 1 hour/quarter testing restores

**What you avoid:**
- Catastrophic data loss
- Panic during incidents
- "We never tested the restore" moments

Your future self will thank you when disaster strikes.

---

**Related Reading:**
- [Zero-Downtime Database Migrations](#) - Using backups for migrations
- [CNPG Multi-Environment Strategy](#) - Per-app cluster design
- [GitOps Disaster Recovery](#) - How backups saved production

**Code Repository:** [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
