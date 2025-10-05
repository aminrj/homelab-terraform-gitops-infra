# Zero-Downtime Database Migrations with CNPG: Upgrading from v1 to v3

*How I migrated n8n's PostgreSQL database from v1 to v3 with zero downtime, using CNPG's recovery features and blue-green deployment patterns.*

## The Migration Challenge

My n8n database evolved through three versions:
- **v1**: Initial single-instance PostgreSQL 15
- **v2**: Upgraded to PostgreSQL 16, still single instance
- **v3**: High-availability with 2 instances, improved backup config

Each migration needed to preserve data while upgrading the cluster. Here's how I did it without downtime.

## Migration Strategy

The pattern:
1. Create new cluster (v3) with recovery from old cluster (v2)
2. Wait for recovery to complete
3. Update application to point to new cluster
4. Verify data integrity
5. Delete old cluster

**Key insight:** CNPG can bootstrap a new cluster from an existing cluster's backups while the old cluster continues running.

## Before Migration: Preparation

### Step 1: Verify Current Cluster

```bash
$ kubectl get clusters -n cnpg-prod
NAME               AGE    INSTANCES   READY   STATUS
n8n-db-cnpg-v2     30d    1           1       Cluster in healthy state

$ kubectl cnpg status n8n-db-cnpg-v2 -n cnpg-prod
Cluster Summary
Name:                   n8n-db-cnpg-v2
Namespace:              cnpg-prod
PostgreSQL Image:       ghcr.io/cloudnative-pg/postgresql:15.3
Primary instance:       n8n-db-cnpg-v2-1
Instances:              1
Ready instances:        1

Continuous Backup status
First Point of Recoverability:  2024-09-15 02:05:14
Working WAL archiving:           OK
Last Successful Backup:          2024-10-03 02:00:32
```

### Step 2: Take Manual Backup

```bash
# Create on-demand backup before migration
cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: n8n-pre-migration-backup
  namespace: cnpg-prod
spec:
  cluster:
    name: n8n-db-cnpg-v2
EOF

# Wait for completion
kubectl wait --for=jsonpath='{.status.phase}'=completed \
  backup/n8n-pre-migration-backup -n cnpg-prod --timeout=600s

# Verify
kubectl describe backup n8n-pre-migration-backup -n cnpg-prod
```

### Step 3: Document Current State

```bash
# Count workflows (example data verification)
kubectl exec -it n8n-db-cnpg-v2-1 -n cnpg-prod -- \
  psql -U postgres -d n8n -c "SELECT COUNT(*) FROM workflow;"

# Document result
echo "Pre-migration workflow count: 42" > migration-verification.txt

# Backup database schema
kubectl exec -it n8n-db-cnpg-v2-1 -n cnpg-prod -- \
  pg_dump -U postgres -d n8n --schema-only > schema-v2-backup.sql
```

## Migration Execution

### Step 4: Create v3 Cluster Configuration

```yaml
# databases/n8n/base/cluster-v3.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: n8n-db-cnpg-v3  # New name
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6  # Upgraded
  instances: 2  # Now HA

  storage:
    size: 20Gi

  # Bootstrap from v2 cluster
  bootstrap:
    recovery:
      source: n8n-v2-cluster

  externalClusters:
    - name: n8n-v2-cluster
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

  # New backup configuration
  backup:
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
    retentionPolicy: 7d

  enablePITR: true

  resources:
    requests:
      memory: 500Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m
```

### Step 5: Deploy New Cluster

```bash
# Apply v3 cluster (old cluster still running)
kubectl apply -f databases/n8n/base/cluster-v3.yaml

# Watch recovery progress
kubectl get cluster n8n-db-cnpg-v3 -n cnpg-prod -w

# Output:
# NAME              AGE   INSTANCES   READY   STATUS
# n8n-db-cnpg-v3    10s   2           0       Cluster is being restored
# n8n-db-cnpg-v3    2m    2           1       Cluster is being restored
# n8n-db-cnpg-v3    5m    2           2       Cluster in healthy state
```

### Step 6: Verify v3 Cluster

```bash
# Check status
kubectl cnpg status n8n-db-cnpg-v3 -n cnpg-prod

# Verify data integrity
kubectl exec -it n8n-db-cnpg-v3-1 -n cnpg-prod -- \
  psql -U postgres -d n8n -c "SELECT COUNT(*) FROM workflow;"

# Should match pre-migration count
# count
# -------
#    42
```

### Step 7: Blue-Green Cutover

Now both clusters are running. Time to switch the application.

**Current state:**
```
n8n-app → n8n-db-cnpg-v2-rw → v2 database (PostgreSQL 15)
          n8n-db-cnpg-v3-rw → v3 database (PostgreSQL 16, HA)
```

**Update application:**

```yaml
# apps/n8n/overlays/prod/kustomization.yaml
patches:
  - target:
      kind: Deployment
      name: n8n
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: n8n-db-cnpg-v3-rw.cnpg-prod.svc.cluster.local
        #      ^^^^^^^^^^^^^^^ Updated from v2 to v3
```

```bash
# Apply change
kubectl apply -k apps/n8n/overlays/prod/

# Watch rollout
kubectl rollout status deployment/n8n -n n8n-prod

# Output:
# Waiting for deployment "n8n" rollout to finish: 1 old replicas are pending termination...
# deployment "n8n" successfully rolled out
```

### Step 8: Verify Application

```bash
# Check pod logs for database connection
kubectl logs -n n8n-prod deployment/n8n --tail=50 | grep -i "database\|postgres"

# Should see successful connection to v3

# Test application functionality
kubectl port-forward -n n8n-prod svc/n8n 5678:5678 &
curl -I http://localhost:5678

# Or access via ingress
curl -I https://n8n.example.com
```

### Step 9: Monitor for Issues

```bash
# Watch for 15 minutes
kubectl get pods -n n8n-prod -w

# Check for errors
kubectl logs -f deployment/n8n -n n8n-prod

# Monitor database
kubectl cnpg status n8n-db-cnpg-v3 -n cnpg-prod
```

**If issues occur:**
```yaml
# Rollback to v2
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: n8n-db-cnpg-v2-rw.cnpg-prod.svc.cluster.local
```

### Step 10: Delete Old Cluster

After 24-48 hours of successful operation:

```bash
# Final verification
kubectl exec -it n8n-db-cnpg-v3-1 -n cnpg-prod -- \
  psql -U postgres -d n8n -c "SELECT COUNT(*) FROM workflow;"

# Delete v2 cluster
kubectl delete cluster n8n-db-cnpg-v2 -n cnpg-prod

# Clean up kustomization
# Remove bootstrap/externalClusters from cluster-v3.yaml
```

## Advanced: Point-in-Time Migration

For critical migrations, restore to a specific point in time:

```yaml
bootstrap:
  recovery:
    source: n8n-v2-cluster
    recoveryTarget:
      targetTime: "2024-10-04 23:59:59.000000+00"  # Just before migration
```

This ensures no transactions are lost during the cutover window.

## Migration Patterns for Different Scenarios

### Pattern 1: Major Version Upgrade (PostgreSQL 15 → 16)

```yaml
# Use latest minor version of new major version
imageName: ghcr.io/cloudnative-pg/postgresql:16.6

# Bootstrap from old version
bootstrap:
  recovery:
    source: oldCluster
```

### Pattern 2: Adding High Availability

```yaml
# Increase instances
instances: 2  # Was 1

# CNPG handles replica creation automatically
```

### Pattern 3: Changing Storage Size

```yaml
# Increase storage
storage:
  size: 40Gi  # Was 20Gi

# Note: Can't decrease, only increase
```

### Pattern 4: Changing Backup Configuration

```yaml
# Update backup retention
backup:
  retentionPolicy: 30d  # Was 7d

# Add backup compression
backup:
  barmanObjectStore:
    data:
      compression: gzip
      jobs: 4  # Parallel compression
```

## Troubleshooting Migrations

### Issue: Recovery Hangs

**Symptoms:**
```
kubectl get cluster n8n-db-cnpg-v3 -n cnpg-prod
# STATUS: "Cluster is being restored" (for >30 minutes)
```

**Debug:**
```bash
# Check pod logs
kubectl logs -n cnpg-prod n8n-db-cnpg-v3-1 -f

# Common errors:
# "could not restore file 000000010000000000000042"
# → WAL file missing, backup incomplete

# "connection to server failed"
# → Azure credentials wrong
```

**Fix:**
```bash
# Verify backup exists
az storage blob list \
  --container-name n8n-prod-backups \
  --account-name homelabstorageaccntprod

# Check secrets
kubectl get secret n8n-db-storage -n cnpg-prod -o yaml
```

### Issue: Data Mismatch After Migration

**Verification:**
```bash
# Before migration
OLD_COUNT=$(kubectl exec -it n8n-db-cnpg-v2-1 -n cnpg-prod -- \
  psql -U postgres -d n8n -tAc "SELECT COUNT(*) FROM workflow")

# After migration
NEW_COUNT=$(kubectl exec -it n8n-db-cnpg-v3-1 -n cnpg-prod -- \
  psql -U postgres -d n8n -tAc "SELECT COUNT(*) FROM workflow")

if [ "$OLD_COUNT" != "$NEW_COUNT" ]; then
  echo "DATA MISMATCH! Old: $OLD_COUNT, New: $NEW_COUNT"
  exit 1
fi
```

### Issue: Application Can't Connect

**Debug:**
```bash
# Check service exists
kubectl get svc -n cnpg-prod | grep n8n-db-cnpg-v3

# Should show:
# n8n-db-cnpg-v3-rw    ClusterIP   10.152.183.XX   5432/TCP
# n8n-db-cnpg-v3-ro    ClusterIP   10.152.183.XX   5432/TCP
# n8n-db-cnpg-v3-r     ClusterIP   10.152.183.XX   5432/TCP

# Test connection from app pod
kubectl exec -it deployment/n8n -n n8n-prod -- \
  nc -zv n8n-db-cnpg-v3-rw.cnpg-prod.svc.cluster.local 5432
```

## Migration Checklist

- [ ] Verify current cluster healthy
- [ ] Take manual backup
- [ ] Document current data state (row counts, etc.)
- [ ] Create v3 cluster configuration
- [ ] Deploy v3 cluster (old cluster still running)
- [ ] Wait for recovery to complete (watch status)
- [ ] Verify data integrity in v3
- [ ] Update application to point to v3
- [ ] Watch rollout (no errors)
- [ ] Monitor for 24-48 hours
- [ ] Test application functionality
- [ ] Delete old cluster
- [ ] Update documentation

## Conclusion

Zero-downtime migrations with CNPG:

**What worked:**
- Blue-green pattern (both clusters running)
- Bootstrap from existing cluster
- Gradual cutover via application config
- Rollback capability

**Time investment:**
- Prep: 30 minutes
- Migration: 10 minutes
- Monitoring: 24 hours
- Total downtime: 0 seconds

**Key learnings:**
- Always take manual backup before migration
- Verify data integrity at each step
- Keep old cluster running until new cluster proven
- Document data state for verification

Database migrations don't have to be scary. With CNPG, they're routine.

---

**Related Reading:**
- [CNPG Backup and Restore Patterns](#) - Backup strategies used in migration
- [CNPG Multi-Environment Strategy](#) - Cluster versioning patterns
- [GitOps Disaster Recovery](#) - What to do when migrations fail

**Code Repository:** [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
