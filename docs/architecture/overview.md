# Architecture Overview

Comprehensive architecture documentation for the GitOps homelab infrastructure.

---

## System Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Developer/Admin                             │
│                     (Git commits, kubectl, az CLI)                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Git Repository (GitHub)                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐ │
│  │  Terraform   │  │  Kustomize   │  │  ArgoCD Applications     │ │
│  │  (IaC)       │  │  (K8s config)│  │  (App definitions)       │ │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘ │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
┌───────────────────────────────┐  ┌──────────────────────────────────┐
│    Terraform (Manual Apply)   │  │  ArgoCD (Auto-Sync)              │
│  - Infrastructure provisioning│  │  - App deployments               │
│  - Azure resources            │  │  - Database clusters             │
│  - Core K8s components        │  │  - Infrastructure updates        │
└───────────┬───────────────────┘  └────────┬─────────────────────────┘
            │                               │
            ▼                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        MicroK8s Cluster                              │
│  ┌────────────────────────────────────────────────────────────────┐│
│  │                    Shared Infrastructure                        ││
│  │  ArgoCD | CNPG Operator | External Secrets | cert-manager      ││
│  │  MetalLB | nginx-ingress | Prometheus                          ││
│  └────────────────────────────────────────────────────────────────┘│
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐│
│  │   Apps   │  │Databases │  │ Secrets  │  │   Backups            ││
│  │          │  │          │  │          │  │                      ││
│  │ Linkding │  │ CNPG Pod │◄─┤ExternalS.│  │ Scheduled: 01:00 UTC ││
│  │ Commafeed│  │ PostgreSQL  │  (Azure KV) │ WAL: Every 5 min   ││
│  │ Wallabag │  │          │  │          │  │ Retention: 7 days    ││
│  │ n8n      │  │          │  │          │  │                      ││
│  │ Listmonk │  │          │  │          │  │                      ││
│  └──────────┘  └────┬─────┘  └──────────┘  └────────┬─────────────┘│
└─────────────────────┼────────────────────────────────┼──────────────┘
                      │                                │
                      ▼                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Azure Cloud                                  │
│  ┌──────────────────┐         ┌──────────────────────────────────┐ │
│  │  Azure Key Vault │         │  Azure Blob Storage              │ │
│  │  - DB credentials│         │  - Base backups                  │ │
│  │  - App secrets   │         │  - WAL archives                  │ │
│  │  - SAS tokens    │         │  - Point-in-time recovery data   │ │
│  └──────────────────┘         └──────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. GitOps with ArgoCD

**Purpose**: Automated deployment and synchronization from Git to Kubernetes

**How it works**:

1. Changes pushed to Git repository
2. ArgoCD detects changes (polling every 3 minutes)
3. Automatically syncs to cluster (if auto-sync enabled)
4. Monitors application health and sync status

**ApplicationSets**: Auto-discover apps in `/apps/{app}/overlays/{env}/` and create ArgoCD applications

**Key Features**:

- Declarative GitOps CD for Kubernetes
- Self-healing and auto-sync capabilities
- Web UI for visualization and management
- RBAC and SSO integration

### 2. Database Management with CloudNative-PG

**Purpose**: Production-grade PostgreSQL on Kubernetes

**Architecture**:

- **Operator**: Manages PostgreSQL cluster lifecycle
- **Clusters**: Primary instance + optional replicas
- **Backup**: Continuous WAL archiving + scheduled base backups
- **Recovery**: Point-in-time recovery from Azure storage

**Features**:

- Automated failover and self-healing
- Continuous backup and point-in-time recovery
- Connection pooling with PgBouncer
- Monitoring with Prometheus metrics

### 3. Secrets Management

**Purpose**: Secure secret storage and synchronization

**Flow**:

```
Azure Key Vault (source of truth)
    ↓
External Secrets Operator (sync engine)
    ↓
Kubernetes Secrets (synchronized)
    ↓
Application Pods (consume secrets)
```

**Security Benefits**:

- Secrets never stored in Git
- Centralized secret management
- Automatic rotation support
- Audit logging in Azure

### 4. Infrastructure as Code with Terraform

**Purpose**: Reproducible infrastructure provisioning

**Environments**:

- **shared**: Core infrastructure (ArgoCD, CNPG, monitoring)
- **prod**: Production resources (Key Vault, storage, apps)
- **qa**: QA/staging environment
- **dev**: Development environment

**Modules**:

- `argocd`: ArgoCD installation and configuration
- `cnpg-operator`: PostgreSQL operator deployment
- `cnpg-cluster`: Database cluster definitions
- `azure-kv`: Key Vault setup and policies
- `azure-storage`: Backup storage containers

---

## Data Flow

### Application Deployment Flow

```
1. Developer commits code
   ↓
2. Git repository updated
   ↓
3. ArgoCD detects change
   ↓
4. ArgoCD syncs to cluster
   ↓
5. Kubernetes deploys/updates pods
   ↓
6. Application running
```

### Secret Synchronization Flow

```
1. Secret stored in Azure Key Vault
   ↓
2. ExternalSecret CR references KV secret
   ↓
3. External Secrets Operator fetches secret
   ↓
4. Operator creates/updates K8s Secret
   ↓
5. Application mounts secret as env var or file
```

### Backup Flow

```
1. Scheduled backup triggers (01:00 UTC daily)
   ↓
2. CNPG takes base backup
   ↓
3. Base backup uploaded to Azure Blob Storage
   ↓
4. Continuous WAL archiving (every 5 min)
   ↓
5. WAL segments uploaded to Azure
   ↓
6. Retention policy applied (7 days)
```

### Restore Flow

```
1. Create restore Cluster CR
   ↓
2. CNPG downloads base backup from Azure
   ↓
3. CNPG replays WAL files
   ↓
4. Database restored to target state
   ↓
5. Application connects to restored database
```

---

## Network Architecture

### Service Communication

```
┌─────────────────────────────────────────────────────┐
│ External Traffic (Internet)                         │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ MetalLB LoadBalancer (External IP)                  │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ nginx-ingress-controller                            │
│ - TLS termination (cert-manager)                    │
│ - Routing based on hostname                         │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴──────────┬──────────────┐
        ▼                     ▼              ▼
┌───────────────┐    ┌───────────────┐   ┌────────────┐
│ App Service   │    │ ArgoCD Service│   │ Grafana    │
│ (ClusterIP)   │    │ (ClusterIP)   │   │ Service    │
└───────┬───────┘    └───────┬───────┘   └─────┬──────┘
        │                    │                   │
        ▼                    ▼                   ▼
┌───────────────┐    ┌───────────────┐   ┌────────────┐
│ App Pods      │    │ ArgoCD Pods   │   │ Grafana Pod│
└───────┬───────┘    └───────────────┘   └────────────┘
        │
        │ (connects to DB)
        ▼
┌──────────────────────────────────────────────────────┐
│ PostgreSQL Service (ClusterIP)                       │
│ - {app}-db-cnpg-v1-rw (read-write)                  │
│ - {app}-db-cnpg-v1-r (read-only)                    │
└──────────────────┬───────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────┐
│ PostgreSQL Pods (StatefulSet-like)                   │
│ - Primary instance                                    │
│ - Optional replicas                                   │
└──────────────────────────────────────────────────────┘
```

### DNS Resolution

**Internal DNS** (CoreDNS):

```
<service>.<namespace>.svc.cluster.local
linkding-db-cnpg-v1-rw.cnpg-prod.svc.cluster.local:5432
```

**External DNS** (optional):

```
app.yourdomain.com → MetalLB LoadBalancer IP
```

---

## Storage Architecture

### Persistent Volume Claims

```
┌─────────────────────────────────────────────────────┐
│ PostgreSQL Pod                                       │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Container                                        │ │
│ │ - Mount: /var/lib/postgresql/data               │ │
│ └──────────────────────┬──────────────────────────┘ │
└────────────────────────┼────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│ PersistentVolumeClaim (PVC)                         │
│ - Size: 15Gi (configurable)                         │
│ - Access: ReadWriteOnce                             │
│ - StorageClass: local-path                          │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│ PersistentVolume (PV)                               │
│ - Provisioned by local-path-provisioner             │
│ - Path: /var/snap/microk8s/common/default-storage  │
└─────────────────────────────────────────────────────┘
```

### Backup Storage

```
┌─────────────────────────────────────────────────────┐
│ CNPG Backup Job                                      │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Azure Blob Storage                                   │
│ Container: {app}-db-clean                           │
│ ├── base/                                           │
│ │   ├── 20251008T010000/ (base backup)             │
│ │   └── 20251009T010000/                           │
│ └── wals/ (WAL archive)                            │
│     ├── 000000010000000000000001.gz                │
│     ├── 000000010000000000000002.gz                │
│     └── ...                                         │
└─────────────────────────────────────────────────────┘
```

---

## Security Architecture

### Authentication & Authorization

**Kubernetes RBAC**:

```
User/ServiceAccount
    ↓
Role/ClusterRole (permissions)
    ↓
RoleBinding/ClusterRoleBinding
    ↓
Resources (pods, services, secrets)
```

**Azure Authentication**:

```
Service Principal (managed identity)
    ↓
Azure RBAC (Key Vault permissions)
    ↓
Key Vault Secrets
    ↓
External Secrets Operator sync
```

### Secret Flow Security

1. **Storage**: Encrypted at rest in Azure Key Vault
2. **Transit**: TLS encryption for all communications
3. **K8s**: Secrets stored base64-encoded (etcd encryption optional)
4. **Access**: Least-privilege service accounts
5. **Rotation**: Automated via External Secrets Operator

### Network Security

- **Internal**: ClusterIP services (no external access by default)
- **Ingress**: TLS termination with cert-manager certificates
- **Egress**: Controlled via network policies (optional)
- **Pod Security**: Security contexts with non-root users

---

## Scalability & Reliability

### High Availability

**Current Setup** (Single instance):

- Single MicroK8s node
- Single PostgreSQL instance per app
- Local storage (no replication)

**Future HA Options**:

- Multi-node MicroK8s cluster
- PostgreSQL replicas for read scaling
- Distributed storage (Ceph/Rook)
- External load balancer

### Disaster Recovery

**RTO** (Recovery Time Objective): < 10 minutes
**RPO** (Recovery Point Objective): < 5 minutes

**Backup Strategy**:

- Continuous WAL archiving (5-minute intervals)
- Daily base backups (01:00 UTC)
- 7-day retention policy
- Point-in-time recovery capability

**Failure Scenarios**:

- Pod failure: Automatic restart by Kubernetes
- Node failure: Requires manual intervention (single node)
- Database corruption: Restore from Azure backup
- Complete cluster loss: Rebuild and restore from backups

---

## Monitoring & Observability

### Metrics Collection

```
┌─────────────────────────────────────────────────────┐
│ Application/Database Pods                            │
│ - Expose /metrics endpoint                           │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Prometheus                                           │
│ - Scrapes metrics every 30s                         │
│ - Stores time-series data                           │
│ - Evaluates alert rules                             │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ Grafana (optional)                                   │
│ - Visualizes metrics                                 │
│ - Pre-built dashboards                              │
└─────────────────────────────────────────────────────┘
```

### Key Metrics

**Database**:

- `cnpg_pg_database_size_bytes`: Database size
- `cnpg_pg_replication_lag`: Replication lag (if replicas exist)
- `cnpg_backends_waiting_total`: Connection pool status

**Applications**:

- HTTP request rate and latency
- Error rates
- Resource usage (CPU, memory)

**Infrastructure**:

- Node resource utilization
- Pod status and restarts
- PVC usage

---

## Cost Optimization

### Azure Resources

| Resource              | Cost Driver            | Optimization                           |
| --------------------- | ---------------------- | -------------------------------------- |
| **Key Vault**         | Transactions           | Cache secrets, reduce sync frequency   |
| **Blob Storage**      | Storage + transactions | Retention policy, lifecycle management |
| **Service Principal** | Free                   | N/A                                    |

### Kubernetes Resources

| Resource    | Optimization               |
| ----------- | -------------------------- |
| **CPU**     | Right-size requests/limits |
| **Memory**  | Monitor actual usage       |
| **Storage** | PVC size, backup retention |

---

## Future Enhancements

### Planned Improvements

1. **High Availability**:

   - Multi-node cluster: add more nodes
   - PostgreSQL replicas
   - Distributed storage

2. **Security Enhancements**:

   - Network policies
   - Pod security standard
   - Image scanning

3. **Observability**:

   - Grafana dashboards
   - Alert manager integration
   - Distributed tracing

4. **Automation**:
   - Automated disaster recovery drills
   - Capacity planning automation
   - Cost optimization automation

---

## Reference Links

- **MicroK8s**: <https://microk8s.io/docs>
- **ArgoCD**: <https://argo-cd.readthedocs.io/>
- **CloudNative-PG**: <https://cloudnative-pg.io/documentation/>
- **External Secrets**: <https://external-secrets.io/latest/>
- **Terraform**: <https://www.terraform.io/docs>
- **Kustomize**: <https://kustomize.io/>

---

**Last Updated**: 2025-10-08
**Architecture Version**: 1.0
