# Linkding Database Backup/Restore Procedures

## Overview

This document describes the working backup and restore procedures for the linkding PostgreSQL database using CloudNative-PG (CNPG) and Azure Blob Storage.

## Current Status ✅

**Successfully Implemented and Tested:**
- ✅ WAL archiving to Azure Blob Storage (`linkding-db-clean` container)
- ✅ GitOps-compatible configuration with base + overlay pattern
- ✅ Scheduled daily backups at 01:00 UTC
- ✅ Manual backup capability
- ✅ Clean storage path to avoid "Expected empty archive" errors
- ✅ Proper Azure credentials integration via External Secrets

## Configuration Architecture

### Storage Location
- **Primary Backup Location**: `https://homelabstorageaccntprod.blob.core.windows.net/linkding-db-clean`
- **WAL Archive Location**: Same container, `wals/` subdirectory
- **Compression**: gzip enabled for both WAL and data

### File Structure
```
databases/linkding/
├── base/
│   └── database.yaml                 # Base cluster configuration with backup setup
├── overlays/prod/
│   ├── kustomization.yaml           # References base + patches + secrets
│   ├── destination-path-patch.yaml  # Production-specific overrides
│   ├── scheduled-backup.yaml        # Daily backup schedule
│   └── secrets.yaml                 # External secrets configuration
```

### Key Configuration Elements

#### Base Configuration (`base/database.yaml`)
- Clean storage path: `linkding-db-clean` container
- Azure credentials from External Secrets
- 14-day retention policy
- gzip compression for WAL and data

#### Production Overrides (`overlays/prod/destination-path-patch.yaml`)
- Storage size: 15Gi
- Storage class: microk8s-hostpath

#### Scheduled Backup (`scheduled-backup.yaml`)
- Daily at 01:00 UTC
- Uses barmanObjectStore method
- Cluster reference: `linkding-db-cnpg-v1`

## Backup Procedures

### Automated Daily Backups
Scheduled backups run automatically at 01:00 UTC daily via:
```bash
kubectl get scheduledbackup linkding-daily-backup -n cnpg-prod
```

### Manual Backup Creation
```bash
kubectl create -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: linkding-manual-backup-$(date +%Y%m%d-%H%M%S)
  namespace: cnpg-prod
spec:
  cluster:
    name: linkding-db-cnpg-v1
EOF
```

### Backup Status Monitoring
```bash
# Check backup status
kubectl get backups -n cnpg-prod | grep linkding

# Check scheduled backup status
kubectl get scheduledbackup linkding-daily-backup -n cnpg-prod

# Check WAL archiving logs
kubectl logs linkding-db-cnpg-v1-1 -n cnpg-prod | grep -E "(Archived WAL|archive command)"
```

## Restore Procedures

### Point-in-Time Recovery
Create a new cluster with recovery configuration:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: linkding-restored
  namespace: cnpg-prod
spec:
  instances: 1
  imageName: "quay.io/enterprisedb/postgresql:16.1"

  storage:
    size: "15Gi"
    storageClass: "microk8s-hostpath"

  bootstrap:
    recovery:
      source: "linkding-clean-backup"
      # Optional: specify target time
      # recoveryTarget:
      #   targetTime: "2025-09-19 08:00:00.00000+00"

  externalClusters:
  - name: "linkding-clean-backup"
    barmanObjectStore:
      destinationPath: https://homelabstorageaccntprod.blob.core.windows.net/linkding-db-clean
      serverName: linkding-db-cnpg-v1
      azureCredentials:
        storageAccount:
          name: linkding-db-storage
          key: container-name
        storageSasToken:
          name: linkding-db-storage
          key: blob-sas
      wal:
        maxParallel: 5
        compression: gzip
      data:
        compression: gzip
```

### Validation Steps

After restore, verify data integrity:
```bash
# Connect to restored cluster
kubectl exec -it linkding-restored-1 -n cnpg-prod -- env PGPASSWORD='<password>' psql -h localhost -U linkding -d linkding

# Verify test data
SELECT * FROM backup_test;

# Expected results should include:
# - test_user_amine
# - backup_validation_data
# - restore_test_entry
# - working_backup_system
# - clean_storage_success
```

## Troubleshooting

### Common Issues and Solutions

#### "Expected empty archive" Error
**Problem**: WAL archiving fails with "Expected empty archive" error
**Solution**: Use clean storage container (`linkding-db-clean`) instead of previously used paths

#### Backup Stuck in Progress
**Problem**: Manual backups show no phase or remain in progress
**Solution**: Wait for completion; WAL archiving must be healthy first. Check logs:
```bash
kubectl logs linkding-db-cnpg-v1-1 -n cnpg-prod | grep -E "(Archived WAL|backup)"
```

#### Restore "No Target Backup Found"
**Problem**: Restore fails with "no target backup found"
**Solution**: Ensure at least one successful base backup exists. Check:
```bash
kubectl get backups -n cnpg-prod | grep linkding
```

### Health Monitoring

#### Check WAL Archiving Health
```bash
# Should show successful WAL archiving
kubectl logs linkding-db-cnpg-v1-1 -n cnpg-prod | grep "Archived WAL file"
```

#### Check Backup Health
```bash
# Should show completed backups
kubectl get backups -n cnpg-prod -o wide | grep linkding
```

#### Check Cluster Health
```bash
# Should show "Cluster in healthy state"
kubectl get cluster linkding-db-cnpg-v1 -n cnpg-prod
```

## Recovery Testing

### Test Data Validation
The system includes test data for backup/restore validation:
```sql
-- Test table structure
CREATE TABLE backup_test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Test data entries
INSERT INTO backup_test (name) VALUES
    ('test_user_amine'),
    ('backup_validation_data'),
    ('restore_test_entry'),
    ('working_backup_system'),
    ('clean_storage_success');
```

## Important Notes

1. **Clean Storage**: Always use the `linkding-db-clean` container to avoid conflicts with old failed backups
2. **WAL Health**: WAL archiving must be healthy before attempting restores
3. **Credentials**: Azure storage credentials are managed via External Secrets Operator
4. **Retention**: Backups are retained for 14 days by default
5. **GitOps**: All changes should be committed to Git for ArgoCD to sync

## Security Considerations

- Database passwords are stored in External Secrets linked to Azure Key Vault
- Azure storage access uses SAS tokens with limited permissions
- Backup data is compressed and stored in Azure Blob Storage with appropriate access controls

## Maintenance

### Regular Checks (Weekly)
1. Verify WAL archiving is healthy
2. Check backup completion status
3. Validate storage usage in Azure
4. Test restore capability (monthly)

### Cleanup (As Needed)
```bash
# Remove old failed backups
kubectl delete backup <backup-name> -n cnpg-prod

# Clean test restore clusters
kubectl delete cluster linkding-restore-test -n cnpg-prod
```