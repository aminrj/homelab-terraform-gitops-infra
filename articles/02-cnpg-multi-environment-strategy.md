# CNPG Multi-Environment Database Strategy: One Cluster or Many?

*How I structure PostgreSQL databases across dev, QA, and production environments using CloudNativePG, and why I chose dedicated clusters over shared infrastructure.*

## The Database Architecture Decision

When you're building a multi-environment Kubernetes homelab, one of the first questions is: how do you handle databases?

Should you:
- **A)** Run one shared PostgreSQL cluster with multiple databases?
- **B)** Run separate PostgreSQL clusters per environment?
- **C)** Run separate PostgreSQL clusters per application per environment?

I chose option C, and here's why it works for a homelab setup.

## My Current Setup

Let's start with what I'm actually running:

```bash
$ kubectl get clusters --all-namespaces
NAMESPACE   NAME                   AGE    INSTANCES   READY   STATUS
cnpg-prod   n8n-db-cnpg-v3         2d     2           2       Cluster in healthy state
cnpg-prod   commafeed-db-cnpg-v1   15d    1           1       Cluster in healthy state
cnpg-prod   linkding-db-cnpg-v1    15d    1           1       Cluster in healthy state
cnpg-prod   listmonk-db-cnpg-v1    15d    2           2       Cluster in healthy state
cnpg-prod   wallabag-db-cnpg-v1    15d    1           1       Cluster in healthy state

cnpg-qa     n8n-db-cnpg-v3         2d     1           1       Cluster in healthy state
cnpg-qa     commafeed-db-cnpg-v1   15d    1           1       Cluster in healthy state
# ... etc for other apps
```

Each application gets its own dedicated PostgreSQL cluster, and each environment (dev/qa/prod) gets its own namespace for database clusters.

**Directory Structure:**
```
databases/
  ├── n8n/
  │   ├── base/
  │   │   └── database.yaml          # Base cluster definition
  │   └── overlays/
  │       ├── prod/
  │       │   ├── kustomization.yaml
  │       │   ├── scheduled-backup.yaml
  │       │   ├── destination-path-patch.yaml
  │       │   └── secrets.yaml
  │       └── qa/
  │           ├── kustomization.yaml
  │           └── ... (similar structure)
  ├── commafeed/
  │   ├── base/
  │   └── overlays/...
  └── linkding/
      ├── base/
      └── overlays/...
```

## Why Dedicated Clusters Per Application?

### Reason 1: Complete Isolation

Each application gets its own PostgreSQL cluster with dedicated resources:

```yaml
# databases/n8n/base/database.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: n8n-db-cnpg-v3
spec:
  instances: 2  # n8n gets 2 instances (HA in prod)

  storage:
    size: 20Gi  # Dedicated storage for n8n

  resources:
    requests:
      memory: 500Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m
```

If n8n's database has issues, crashes, or needs maintenance, it doesn't affect commafeed or linkding. True isolation.

### Reason 2: Independent Lifecycle Management

Each cluster has its own version and can be upgraded independently:

```yaml
# n8n using PostgreSQL 16
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6

# commafeed still on PostgreSQL 15
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:15.3
```

I can test PostgreSQL upgrades on one app without risking others. This is especially valuable when an application has specific PostgreSQL extension requirements.

### Reason 3: Granular Backup and Restore

Each cluster has its own backup schedule and retention policy:

```yaml
# databases/n8n/overlays/prod/scheduled-backup.yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: n8n-daily-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  backupOwnerReference: cluster
  cluster:
    name: n8n-db-cnpg-v3
  suspend: false
```

**Critical workflows** (like n8n) get frequent backups. **Read-only apps** (like linkding) can have less frequent backups, saving storage costs.

### Reason 4: Easy Cross-Environment Restores

With dedicated clusters, I can easily restore QA data to dev, or prod data to QA for testing:

```yaml
# databases/n8n/overlays/qa/restore-from-prod.yaml
patches:
  - target:
      kind: Cluster
      name: n8n-db-cnpg-v3
    patch: |-
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
              destinationPath: https://storage.blob.core.windows.net/n8n-prod-backups
              azureCredentials:
                storageAccount:
                  name: n8n-db-storage
                  key: container-name
```

This lets me test database migrations or debug production issues with real data in a safe environment.

## The Multi-Environment Pattern

Here's how I structure environments using Kustomize overlays:

### Base Configuration (Shared)

```yaml
# databases/commafeed/base/database.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: commafeed-db-cnpg-v1
spec:
  description: Postgres cluster for commafeed
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  instances: 1  # Overridden in prod for HA

  storage:
    size: 15Gi

  resources:
    requests:
      memory: 600Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m

  bootstrap:
    initdb:
      database: commafeed
      owner: commafeed
      secret:
        name: commafeed-db-creds

  # Backup configuration (path overridden per environment)
  backup:
    barmanObjectStore:
      destinationPath: # Replaced in overlays
      azureCredentials:
        storageAccount:
          name: commafeed-db-storage
          key: container-name
        storageSasToken:
          name: commafeed-db-storage
          key: blob-sas
      wal:
        compression: gzip
      data:
        compression: gzip
    retentionPolicy: 7d
```

### Production Overlay

```yaml
# databases/commafeed/overlays/prod/kustomization.yaml
namespace: cnpg-prod

resources:
  - ../../base
  - scheduled-backup.yaml
  - secrets.yaml

patches:
  - path: destination-path-patch.yaml
```

```yaml
# databases/commafeed/overlays/prod/destination-path-patch.yaml
- op: replace
  path: /spec/backup/barmanObjectStore/destinationPath
  value: https://homelabstorageaccntprod.blob.core.windows.net/commafeed-prod-backups
```

```yaml
# databases/commafeed/overlays/prod/scheduled-backup.yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: commafeed-daily-backup
spec:
  schedule: "0 2 * * *"
  backupOwnerReference: cluster
  cluster:
    name: commafeed-db-cnpg-v1
```

### QA Overlay

```yaml
# databases/commafeed/overlays/qa/kustomization.yaml
namespace: cnpg-qa

resources:
  - ../../base
  - scheduled-backup.yaml
  - secrets.yaml

patches:
  - path: destination-path-patch.yaml
  - target:
      kind: Cluster
      name: commafeed-db-cnpg-v1
    patch: |-
      - op: replace
        path: /spec/instances
        value: 1  # QA doesn't need HA

      - op: replace
        path: /spec/resources/requests/memory
        value: 300Mi  # Less resources for QA
```

```yaml
# databases/commafeed/overlays/qa/destination-path-patch.yaml
- op: replace
  path: /spec/backup/barmanObjectStore/destinationPath
  value: https://homelabstorageaccntprod.blob.core.windows.net/commafeed-qa-backups
```

## Resource Allocation Strategy

Homelabs have limited resources. Here's how I allocate them:

### Production Environment
- **High Availability:** 2 instances for critical apps (n8n, listmonk)
- **More Resources:** Higher CPU and memory limits
- **Frequent Backups:** Daily backups with 7-day retention
- **Monitoring:** Full Prometheus metrics enabled

```yaml
# Production: n8n gets HA
spec:
  instances: 2
  resources:
    requests:
      memory: 500Mi
      cpu: 100m
    limits:
      memory: 1Gi
      cpu: 500m
```

### QA Environment
- **Single Instance:** No HA needed for testing
- **Reduced Resources:** Half the memory of production
- **Weekly Backups:** Less frequent backup schedule
- **Monitoring:** Basic metrics only

```yaml
# QA: n8n single instance
spec:
  instances: 1
  resources:
    requests:
      memory: 250Mi
      cpu: 50m
    limits:
      memory: 500Mi
      cpu: 250m
```

### Dev Environment (Optional)
- **Minimal Resources:** Just enough to run
- **No Backups:** Ephemeral data
- **Can be deleted:** Free resources when not actively developing

## Secrets Management Per Environment

Each environment has its own database credentials using External Secrets Operator:

```yaml
# databases/commafeed/overlays/prod/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: commafeed-db-creds
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault-prod
    kind: SecretStore
  target:
    name: commafeed-db-creds
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: commafeed-db-username-prod
    - secretKey: password
      remoteRef:
        key: commafeed-db-password-prod
    - secretKey: POSTGRES_USER
      remoteRef:
        key: commafeed-db-username-prod
    - secretKey: POSTGRES_PASSWORD
      remoteRef:
        key: commafeed-db-password-prod
```

This means:
- Prod credentials are different from QA
- Credentials are stored securely in Azure Key Vault
- Rotating credentials doesn't require touching Git

## Connecting Applications to Databases

Applications connect via Kubernetes service discovery:

```yaml
# apps/commafeed/overlays/prod/kustomization.yaml
namespace: commafeed-prod

patches:
  - target:
      kind: Deployment
      name: commafeed
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: commafeed-db-cnpg-v1-rw.cnpg-prod.svc.cluster.local
        #      ^cluster-name       ^namespace  ^service-type
```

**Service naming pattern:**
- `{cluster-name}-rw` = Read-Write service (primary)
- `{cluster-name}-ro` = Read-Only service (replicas)
- `{cluster-name}-r` = Any instance (read)

**Full DNS:**
```
{cluster-name}-{service-type}.{namespace}.svc.cluster.local
```

Example for n8n in prod:
```
n8n-db-cnpg-v3-rw.cnpg-prod.svc.cluster.local
```

## Backup Strategy Across Environments

I use Azure Blob Storage with different containers per environment:

```
Azure Storage Account: homelabstorageaccntprod
├── commafeed-prod-backups/    # Production backups
├── commafeed-qa-backups/       # QA backups
├── n8n-prod-backups/
├── n8n-qa-backups/
├── linkding-prod-backups/
└── ... etc
```

**Backup schedule:**
```yaml
# Production: Daily at 2 AM
schedule: "0 2 * * *"
retentionPolicy: 7d  # Keep 7 days of backups

# QA: Weekly on Sunday
schedule: "0 3 * * 0"
retentionPolicy: 7d

# Dev: No backups (ephemeral)
```

## When to Use This Pattern

**✅ Use dedicated clusters per app when:**
- You have 5-20 applications (sweet spot for homelab)
- Applications have different performance requirements
- You want to test database upgrades safely
- You need per-app backup policies
- You value isolation over resource efficiency

**❌ Consider shared clusters when:**
- You have 50+ applications (management overhead)
- All apps have similar requirements
- Resources are extremely limited
- You're running in a real production environment with a DBA team

## Resource Impact

Here's what this strategy costs in my homelab:

**Per database cluster:**
- Memory: 300Mi-1Gi per instance
- CPU: 50m-500m per instance
- Storage: 10Gi-20Gi per cluster

**Total for 5 applications (prod):**
- Memory: ~4Gi (8 PostgreSQL instances)
- CPU: ~1 core
- Storage: ~80Gi

**Optimization tip:** I only run prod permanently. QA is created on-demand for testing, then deleted to free resources:

```bash
# Delete QA when not needed
kubectl delete namespace cnpg-qa

# Recreate when needed
kubectl apply -k databases/n8n/overlays/qa/
kubectl apply -k databases/commafeed/overlays/qa/
```

Configurations stay in Git, so recreation is instant.

## Disaster Recovery Benefits

This architecture shines during incidents. Remember my production deletion incident?

**What survived:**
```bash
$ kubectl get clusters -n cnpg-prod
# All healthy - databases in separate namespace
```

**What was deleted:**
```bash
$ kubectl get deployments -n n8n-prod
# Empty - application namespace was deleted
```

**Recovery:**
```bash
kubectl apply -k apps/n8n/overlays/prod/
# App reconnects to existing database automatically
```

The separation of database clusters from application deployments meant data survived the incident completely untouched.

## Monitoring and Observability

CNPG provides excellent Prometheus metrics per cluster:

```yaml
# In base database.yaml
monitoring:
  enablePodMonitor: true
  podMonitorMetricRelabelings:
    - sourceLabels: [__name__]
      regex: 'cnpg_.*|pg_.*'
      action: keep
```

**Key metrics I monitor:**
- `cnpg_pg_database_size_bytes` - Database growth
- `cnpg_pg_stat_replication_lag_bytes` - Replication lag (HA clusters)
- `cnpg_pg_postmaster_start_time` - Uptime
- `cnpg_backup_last_successful_timestamp` - Backup freshness

With dedicated clusters, I can set different alert thresholds per application.

## Migration Path: Upgrading Between Cluster Versions

When I need to upgrade a database cluster (like n8n's v1 → v2 → v3 migration), this architecture makes it safe:

**Step 1:** Create new cluster with recovery from old cluster

```yaml
# databases/n8n/overlays/prod/cluster-v3.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: n8n-db-cnpg-v3  # New name
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  instances: 2

  bootstrap:
    recovery:
      source: n8n-v2-cluster

  externalClusters:
    - name: n8n-v2-cluster
      barmanObjectStore:
        destinationPath: https://storage.blob.core.windows.net/n8n-prod-backups
        # ... credentials
```

**Step 2:** Wait for recovery to complete

```bash
kubectl cnpg status n8n-db-cnpg-v3 -n cnpg-prod
# Wait until: Cluster in healthy state
```

**Step 3:** Update application to point to new cluster

```yaml
# apps/n8n/overlays/prod/kustomization.yaml
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: n8n-db-cnpg-v3-rw.cnpg-prod.svc.cluster.local
        #      ^^^^^^^^^^^^^^^ Updated cluster name
```

**Step 4:** Apply and verify

```bash
kubectl apply -k apps/n8n/overlays/prod/
# n8n pod restarts and connects to new database
```

**Step 5:** Delete old cluster after validation

```bash
kubectl delete cluster n8n-db-cnpg-v2 -n cnpg-prod
```

Zero downtime if you're careful, and you can always rollback by changing the service name back.

## Conclusion

Dedicated PostgreSQL clusters per application per environment might seem like overkill for a homelab, but it provides:

1. **True isolation** - Problems don't cascade
2. **Flexible resource allocation** - Give resources where needed
3. **Independent lifecycles** - Upgrade/downgrade safely
4. **Granular backups** - Different policies per app
5. **Easy cross-environment testing** - Restore prod to QA
6. **Simple disaster recovery** - Apps and data separate

The resource overhead is real but manageable with on-demand QA environments. And in a homelab where you're learning and experimenting, the operational benefits far outweigh the resource costs.

**Next Steps:**
- [CNPG Backup and Restore Patterns](#) - Deep dive into backup strategies
- [Zero-Downtime Database Migrations](#) - How I migrated n8n from v1 to v3
- [External Secrets + CNPG](#) - Secure credential management

**Code Repository:** All configurations at [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
