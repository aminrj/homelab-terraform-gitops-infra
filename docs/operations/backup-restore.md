# Backup and Restore Operations

**Critical Reference**: Detailed procedures for backing up and restoring PostgreSQL databases from Azure Blob Storage.

---

## Overview

All PostgreSQL databases use **CloudNative-PG (CNPG)** with automated backups to Azure Blob Storage. This provides:

- **Continuous WAL archiving** for point-in-time recovery (PITR)
- **Scheduled daily backups** at 01:00 UTC
- **7-day retention policy** for production
- **Manual backup capability** for on-demand snapshots
- **Verified restore procedures** tested and documented

---

## Backup Architecture

### Storage Structure

```
Azure Blob Storage
├── {app-name}-db-clean/          # Primary backup source
│   ├── base/                     # Base backups
│   └── wals/                     # WAL archive files
├── {app-name}-db-restore-v2/     # Active cluster backups
│   ├── base/
│   └── wals/
```

### Backup Types

1. **WAL Archiving**: Continuous transaction log shipping (every 5 minutes)
2. **Base Backup**: Full database snapshot (daily at 01:00 UTC)
3. **Manual Backup**: On-demand full backup for critical changes

---

## Database Inventory

| Application | Database Name | User      | Namespace | Backup Container   |
| ----------- | ------------- | --------- | --------- | ------------------ |
| linkding    | linkding      | linkding  | cnpg-prod | linkding-db-clean  |
| commafeed   | commafeed     | commafeed | cnpg-prod | commafeed-db-clean |
| wallabag    | wallabag      | wallabag  | cnpg-prod | wallabag-db-clean  |
| n8n         | n8n           | n8n       | cnpg-prod | n8n-db-restore-new |
| listmonk    | listmonk      | listmonk  | cnpg-prod | listmonk-db-clean  |

---

## Monitoring Backups

### Check Backup Status

```bash
# View all scheduled backups
kubectl get scheduledbackups -n cnpg-prod

# Check recent backups
kubectl get backups -n cnpg-prod --sort-by=.metadata.creationTimestamp

# Check specific backup details
kubectl describe backup <backup-name> -n cnpg-prod
```

### Verify WAL Archiving

```bash
# Check WAL archiving for all databases
for cluster in linkding commafeed wallabag n8n listmonk; do
  echo "=== $cluster WAL archiving ==="
  kubectl logs ${cluster}-db-cnpg-v1-1 -n cnpg-prod --tail=10 | grep "Archived WAL"
done

# Check cluster backup status
kubectl get cluster <cluster-name> -n cnpg-prod -o jsonpath='{.status.lastSuccessfulBackup}'
```

### Check Storage Connectivity

```bash
# Verify Azure credentials are synced
kubectl get externalsecrets -n cnpg-prod | grep storage

# Check storage secrets exist
kubectl get secrets -n cnpg-prod | grep storage

# Verify ClusterSecretStore
kubectl describe clustersecretstore azure-kv-store-prod
```

---

## Creating Manual Backups

### On-Demand Backup

Use before major changes, migrations, or as extra precaution:

```bash
# Create manual backup with timestamp
APP_NAME="linkding"  # Change to your app
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

kubectl cnpg backup ${APP_NAME}-db-cnpg-v1 \
  --backup-name ${APP_NAME}-manual-${TIMESTAMP} \
  -n cnpg-prod

# Monitor backup progress
kubectl get backup ${APP_NAME}-manual-${TIMESTAMP} -n cnpg-prod -w

# Verify backup completion
kubectl describe backup ${APP_NAME}-manual-${TIMESTAMP} -n cnpg-prod
```

### Pre-Upgrade Backup

```bash
# Before upgrading an application or database
APP_NAME="commafeed"

kubectl cnpg backup ${APP_NAME}-db-cnpg-v1 \
  --backup-name ${APP_NAME}-pre-upgrade-$(date +%Y%m%d) \
  -n cnpg-prod
```

---

## Restoring from Backup

### Method 1: Full Cluster Restore (Recommended)

**Use Case**: Complete data loss, cluster corruption, disaster recovery

**Recovery Time**: 2-5 minutes for restore + database startup

#### Step 1: Create Restore Cluster Configuration

Create a new cluster that bootstraps from backup:

```yaml
# restore-{app-name}.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: {app-name}-db-cnpg-v1-restore
  namespace: cnpg-prod
spec:
  description: Restore of {app-name} database from Azure backup
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  instances: 1  # Start with single instance

  inheritedMetadata:
    labels:
      app: {app-name}-database-restore
      policy-type: database

  resources:
    requests:
      memory: 600Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m

  storage:
    size: 15Gi
    storageClass: local-path

  bootstrap:
    recovery:
      source: clusterBackup
      database: {database-name}
      owner: {database-user}
      secret:
        name: {app-name}-db-creds

  externalClusters:
    - name: clusterBackup
      barmanObjectStore:
        destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/{app-name}-db-clean
        endpointURL: https://homelabstorageaccntprod.blob.core.windows.net
        serverName: {app-name}-db-cnpg-v1
        azureCredentials:
          storageAccount:
            name: {app-name}-db-storage
            key: container-name
          storageSasToken:
            name: {app-name}-db-storage
            key: blob-sas
        wal:
          compression: gzip
```

#### Step 2: Apply Restore Configuration

```bash
# Apply the restore cluster
kubectl apply -f restore-{app-name}.yaml

# Monitor restore progress
kubectl get cluster {app-name}-db-cnpg-v1-restore -n cnpg-prod -w

# Watch pods starting
kubectl get pods -n cnpg-prod | grep restore

# Check restore logs
kubectl logs {app-name}-db-cnpg-v1-restore-1-full-recovery-* -n cnpg-prod -f
```

> ⚠️ **Check the backup container path before restoring**  
> Look up the current production cluster to confirm the correct `destinationPath`.  
> For example, `n8n` stores its backups in `https://homelabstorageaccntprod.blob.core.windows.net/n8n-db-restore-new`
> instead of the default `{app-name}-db-clean`. Run  
> `kubectl get cluster <cluster-name> -n cnpg-prod -o yaml | grep -n destinationPath` to verify.

#### Step 3: Verify Restore Success

```bash
# Check cluster status
kubectl get cluster {app-name}-db-cnpg-v1-restore -n cnpg-prod

# Should show: "Cluster in healthy state"

# Test database connectivity
kubectl exec {app-name}-db-cnpg-v1-restore-1 -n cnpg-prod -- \
  psql -U postgres -d {database-name} -c "SELECT count(*) FROM pg_stat_database WHERE datname='{database-name}';"

# Check data is present (example for linkding)
kubectl exec {app-name}-db-cnpg-v1-restore-1 -n cnpg-prod -- \
  psql -U postgres -d {database-name} -c "SELECT count(*) FROM users;"
```

#### Step 4: Point Application to Restored Database

**Option A**: Update application deployment to use new database service:

```bash
# New database service endpoint:
{app-name}-db-cnpg-v1-restore-rw.cnpg-prod.svc.cluster.local:5432
```

Update in `apps/{app-name}/overlays/prod/database-connection.yaml` or deployment environment variables.

**Option B**: Promote restored cluster to primary (advanced):

```bash
# Scale down original cluster
kubectl scale cluster {app-name}-db-cnpg-v1 -n cnpg-prod --replicas=0

# Rename services to use restored cluster
# This requires updating Kustomize configurations
```

---

### Method 2: Point-in-Time Recovery (PITR)

**Use Case**: Restore to specific timestamp (before accidental deletion, corruption)

Add to restore cluster spec:

```yaml
bootstrap:
  recovery:
    source: clusterBackup
    database: {database-name}
    owner: {database-user}
    secret:
      name: {app-name}-db-creds
    recoveryTarget:
      targetTime: "2025-10-08 10:00:00 UTC"  # Specific timestamp
```

**Other recovery target options:**

```yaml
recoveryTarget:
  # Option 1: Specific timestamp (most common)
  targetTime: "2025-10-08 10:00:00 UTC"

  # Option 2: Specific transaction LSN
  targetLSN: "0/1B000028"

  # Option 3: Named restore point
  targetName: "before-migration"

  # Option 4: End of available WAL
  targetImmediate: true
```

---

## Application-Specific Restore Examples

### Linkding Restore

```bash
# Linkding database details
# Database: linkding, User: linkding
# Service after restore: linkding-db-cnpg-v1-restore-rw.cnpg-prod.svc.cluster.local

# Create restore file
cat > restore-linkding.yaml <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: linkding-db-cnpg-v1-restore
  namespace: cnpg-prod
spec:
  description: Restore of linkding database
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  instances: 1

  storage:
    size: 15Gi
    storageClass: local-path

  resources:
    requests:
      memory: 600Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m

  bootstrap:
    recovery:
      source: clusterBackup
      database: linkding
      owner: linkding
      secret:
        name: linkding-db-creds

  externalClusters:
    - name: clusterBackup
      barmanObjectStore:
        destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/linkding-db-clean
        endpointURL: https://homelabstorageaccntprod.blob.core.windows.net
        serverName: linkding-db-cnpg-v1
        azureCredentials:
          storageAccount:
            name: linkding-db-storage
            key: container-name
          storageSasToken:
            name: linkding-db-storage
            key: blob-sas
        wal:
          compression: gzip
EOF

# Apply restore
kubectl apply -f restore-linkding.yaml

# Monitor
kubectl get cluster linkding-db-cnpg-v1-restore -n cnpg-prod -w
```

### Commafeed Restore

```bash
# Commafeed database details
# Database: commafeed, User: commafeed

cat > restore-commafeed.yaml <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: commafeed-db-cnpg-v1-restore
  namespace: cnpg-prod
spec:
  description: Restore of commafeed database
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  instances: 1

  storage:
    size: 15Gi
    storageClass: local-path

  resources:
    requests:
      memory: 600Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m

  bootstrap:
    recovery:
      source: clusterBackup
      database: commafeed
      owner: commafeed
      secret:
        name: commafeed-db-creds

  externalClusters:
    - name: clusterBackup
      barmanObjectStore:
        destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/commafeed-db-clean
        endpointURL: https://homelabstorageaccntprod.blob.core.windows.net
        serverName: commafeed-db-cnpg-v1
        azureCredentials:
          storageAccount:
            name: commafeed-db-storage
            key: container-name
          storageSasToken:
            name: commafeed-db-storage
            key: blob-sas
        wal:
          compression: gzip
EOF

kubectl apply -f restore-commafeed.yaml
```

### n8n Restore (validated)

```bash
# n8n database details
# Database: n8n, User: n8n
# Production backups live in the n8n-db-restore-new container.

cat > restore-n8n.yaml <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: n8n-db-cnpg-v1-restore
  namespace: cnpg-prod
spec:
  description: Restore of n8n database
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  instances: 1

  storage:
    size: 15Gi
    storageClass: local-path

  resources:
    requests:
      memory: 600Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m

  bootstrap:
    recovery:
      source: clusterBackup
      database: n8n
      owner: n8n
      secret:
        name: n8n-db-creds

  externalClusters:
    - name: clusterBackup
      barmanObjectStore:
        destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/n8n-db-restore-new
        endpointURL: https://homelabstorageaccntprod.blob.core.windows.net
        serverName: n8n-db-cnpg-v5
        azureCredentials:
          storageAccount:
            name: n8n-db-storage
            key: container-name
          storageSasToken:
            name: n8n-db-storage
            key: blob-sas
        wal:
          compression: gzip
EOF

kubectl apply -f restore-n8n.yaml
kubectl wait --for=condition=Ready pod -l cnpg.io/cluster=n8n-db-cnpg-v1-restore -n cnpg-prod --timeout=5m

# Validate restored data matches production
kubectl exec -n cnpg-prod n8n-db-cnpg-v1-restore-1 -- \
  psql -U postgres -d n8n -c 'SELECT COUNT(*) AS workflows FROM "workflow_entity";'
kubectl exec -n cnpg-prod n8n-db-cnpg-v1-restore-1 -- \
  psql -U postgres -d n8n -c 'SELECT COUNT(*) AS credentials FROM "credentials_entity";'

# (Latest test on 2025-10-13 returned 7 workflows and 5 credentials.)

# Clean up when done
kubectl delete cluster n8n-db-cnpg-v1-restore -n cnpg-prod
```

---

## Backup Validation & Testing

### Monthly Restore Test

**Best Practice**: Test restore procedures monthly to ensure backups are valid.

```bash
#!/bin/bash
# monthly-restore-test.sh

APP_NAME="linkding"  # Change to test different apps
TIMESTAMP=$(date +%Y%m%d)

echo "Testing restore for ${APP_NAME} on ${TIMESTAMP}"

# 1. Create test restore cluster
kubectl apply -f restore-${APP_NAME}.yaml

# 2. Wait for cluster to be ready
kubectl wait --for=condition=Ready cluster/${APP_NAME}-db-cnpg-v1-restore -n cnpg-prod --timeout=600s

# 3. Verify data integrity
RECORD_COUNT=$(kubectl exec ${APP_NAME}-db-cnpg-v1-restore-1 -n cnpg-prod -- \
  psql -U postgres -d ${APP_NAME} -t -c "SELECT count(*) FROM users;")

echo "Record count in restored database: ${RECORD_COUNT}"

# 4. Cleanup test cluster
kubectl delete cluster ${APP_NAME}-db-cnpg-v1-restore -n cnpg-prod

echo "Restore test complete for ${APP_NAME}"
```

---

## Troubleshooting Restore Issues

### Issue: "Expected empty archive" Error

**Cause**: Storage path contamination or existing cluster in recovery state

**Solution**:

```bash
# Use fresh `-clean` storage paths
# Verify destinationPath uses correct container
kubectl get cluster <name> -n cnpg-prod -o yaml | grep destinationPath

# Ensure using: {app-name}-db-clean (not -restore or -restore-v2)
```

### Issue: WAL Archiving Failures

**Cause**: Invalid Azure credentials or SAS token expired

**Solution**:

```bash
# Check external secret sync status
kubectl describe externalsecret <app>-db-storage -n cnpg-prod

# Verify SAS token in Azure Key Vault is valid
# Rotate SAS token if expired (see Azure portal)

# Restart cluster to pick up new credentials
kubectl rollout restart cluster <app>-db-cnpg-v1 -n cnpg-prod
```

### Issue: Restore Hangs or Times Out

**Cause**: Network connectivity, large backup size, or missing WAL files

**Solution**:

```bash
# Check restore pod logs
kubectl logs <app>-db-cnpg-v1-restore-1-full-recovery-* -n cnpg-prod

# Check for missing WAL segments
# Look for: "could not open file" or "requested WAL segment not found"

# Verify Azure storage connectivity
kubectl exec <app>-db-cnpg-v1-restore-1 -n cnpg-prod -- \
  curl -I https://homelabstorageaccntprod.blob.core.windows.net/<app>-db-clean
```

### Issue: Application Can't Connect After Restore

**Cause**: Database credentials mismatch or service endpoint incorrect

**Solution**:

```bash
# Verify database user exists
kubectl exec <app>-db-cnpg-v1-restore-1 -n cnpg-prod -- \
  psql -U postgres -d <database> -c "\du"

# Check application is using correct service endpoint
kubectl get svc -n cnpg-prod | grep restore

# Verify credentials match
kubectl get secret <app>-db-creds -n cnpg-prod -o yaml
```

---

## Backup Retention & Cleanup

### Retention Policy

- **Production**: 7-day retention (configurable in scheduled-backup.yaml)
- **WAL archives**: Kept until base backup expires
- **Manual backups**: No automatic cleanup

### Manual Cleanup

```bash
# List all backups
kubectl get backups -n cnpg-prod

# Delete old manual backup
kubectl delete backup <backup-name> -n cnpg-prod

# Delete failed backups
kubectl get backups -n cnpg-prod | grep Failed | awk '{print $1}' | xargs kubectl delete backup -n cnpg-prod
```

---

## Recovery Time & Point Objectives

| Metric                             | Target     | Typical     |
| ---------------------------------- | ---------- | ----------- |
| **RTO** (Recovery Time Objective)  | < 10 min   | 3-5 min     |
| **RPO** (Recovery Point Objective) | < 5 min    | 1-5 min     |
| **Backup Frequency**               | Daily      | 01:00 UTC   |
| **WAL Archive Frequency**          | Continuous | Every 5 min |

---

## Emergency Contacts & Escalation

For critical database issues:

1. Check this documentation first
2. Review cluster logs: `kubectl logs <cluster>-1 -n cnpg-prod`
3. Check CNPG operator logs: `kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg`
4. Consult Azure portal for storage/credential issues
5. Escalate if data loss is imminent

---

**Last Updated**: 2025-10-08
**Next Review**: Monthly restore testing and quarterly documentation update
