# Homelab GitOps Infrastructure

**Production-ready Kubernetes homelab** managed via GitOps with Terraform, ArgoCD, and Azure integration.

![Architecture](https://img.shields.io/badge/Architecture-GitOps-blue)
![Kubernetes](https://img.shields.io/badge/K8s-MicroK8s-326CE5)
![Database](https://img.shields.io/badge/Database-PostgreSQL%20CNPG-336791)
![Backup](https://img.shields.io/badge/Backup-Azure%20Storage-0089D6)

---

## 🚀 Quick Start

### New Cluster Bootstrap (current way, 2026-10)

The cluster itself (VMs, MicroK8s, kubeconfig, DNS names) comes from
[homelab-foundation](../homelab-foundation) (`make vms-apply`, `make k8s-apply`). Then, here:

```bash
cp environments/shared/backend.hcl.example environments/shared/backend.hcl   # once per machine
make shared-init
make shared-plan      # read it
make shared-apply     # Traefik, cert-manager, ArgoCD, monitoring, CNPG, ESO + their bootstrap secrets
```

No secret is created by hand: Terraform reads Key Vault (ArgoCD's repo key, the Cloudflare token)
and gives External Secrets its own rotating password (`modules/bootstrap-secrets`). ArgoCD then
syncs `argocd/` from `main`; apps and databases are listed explicitly in the two ApplicationSets.
How to reach each service: `homelab-foundation/docs/services.md`.
`docs/bootstrap/01-new-cluster-bootstrap.md` describes the older, manual path.

# 4. Deploy production
cd ../prod
terraform init && terraform apply

# 5. Configure secrets
kubectl create secret generic azure-creds -n external-secrets \
  --from-literal=client-id="$(terraform output -raw client_id)" \
  --from-literal=client-secret="$(terraform output -raw client_secret)"
```

**Full Instructions**: [docs/bootstrap/01-new-cluster-bootstrap.md](docs/bootstrap/01-new-cluster-bootstrap.md)

---

## 📋 What's Inside

### Core Infrastructure

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **ArgoCD** | GitOps deployment automation | `argocd` |
| **CloudNative-PG** | PostgreSQL operator | `cnpg-system` |
| **External Secrets** | Azure Key Vault integration | `external-secrets` |
| **cert-manager** | TLS certificate management | `cert-manager` |
| **MetalLB** | Load balancer | `metallb-system` |
| **Prometheus** | Monitoring and alerting | `monitoring` |

### Applications

| Application | Description | Database | Environment |
|-------------|-------------|----------|-------------|
| **linkding** | Bookmark manager | PostgreSQL | prod |
| **commafeed** | RSS feed reader | PostgreSQL | prod |
| **wallabag** | Read-it-later service | PostgreSQL | prod |
| **n8n** | Workflow automation | PostgreSQL | prod |
| **listmonk** | Newsletter/mailing | PostgreSQL | prod |
| **threat-intel** | Threat intelligence automation & research pipeline | PostgreSQL | prod |

### Backup System

- **Daily automated backups** at 01:00 UTC
- **Continuous WAL archiving** every 5 minutes
- **7-day retention** for production
- **Point-in-time recovery** capability
- **Azure Blob Storage** for backup storage

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Git Repository                          │
│              (Single Source of Truth)                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ├─── Terraform Modules
                         │    ├── ArgoCD
                         │    ├── CNPG
                         │    ├── External Secrets
                         │    └── Azure Integration
                         │
                         └─── Kustomize Applications
                              ├── apps/{app}/overlays/{env}/
                              ├── databases/{app}/overlays/{env}/
                              └── infrastructure/{component}/overlays/{env}/

                         ↓ ArgoCD Auto-Sync

┌─────────────────────────────────────────────────────────────┐
│                    MicroK8s Cluster                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Applications │  │  Databases   │  │Infrastructure│     │
│  │  (Deployments)│  │  (CNPG)      │  │  (Core)      │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ├─── Secrets ──→ Azure Key Vault
                         └─── Backups ──→ Azure Blob Storage
```

**Detailed Architecture**: [docs/architecture/overview.md](docs/architecture/overview.md)

---

## 📖 Documentation

### Getting Started

- **[Bootstrap New Cluster](docs/bootstrap/01-new-cluster-bootstrap.md)** - Complete setup from scratch (60 min)
- **[Backup & Restore](docs/operations/backup-restore.md)** - Database backup and recovery procedures
- **[Disaster Recovery](docs/operations/disaster-recovery.md)** - Emergency runbooks for critical failures
- **[Troubleshooting](docs/operations/troubleshooting.md)** - Common issues and solutions

### Operations

- **Daily Tasks**:
  - Monitor ArgoCD sync status
  - Check backup completion
  - Review Prometheus alerts

- **Weekly Tasks**:
  - Test database restore for one app
  - Review security updates
  - Check storage usage

- **Monthly Tasks**:
  - Full disaster recovery drill
  - Update documentation
  - Rotate credentials

### Reference

- **[Architecture Overview](docs/architecture/overview.md)** - System design and patterns
- **[CLAUDE.md](CLAUDE.md)** - Claude Code assistant guidance
- **[Old Docs](README-DEPLOYMENT.md)** - Legacy deployment instructions (deprecated)

---

## 🔧 Common Operations

### Check System Health

```bash
# Quick health check
kubectl get nodes
kubectl get pods -A | grep -v Running
kubectl get applications -n argocd
kubectl get clusters -n cnpg-prod
```

### Manual Database Backup

```bash
APP_NAME="linkding"  # or commafeed, wallabag, n8n, listmonk
kubectl cnpg backup ${APP_NAME}-db-cnpg-v1 \
  --backup-name ${APP_NAME}-manual-$(date +%Y%m%d) \
  -n cnpg-prod
```

### Restore Database from Azure

```bash
# Use pre-configured restore files
kubectl apply -f databases/<app-name>/overlays/prod/restore-from-azure.yaml

# Monitor restore
kubectl get cluster <app>-db-cnpg-v1-restore -n cnpg-prod -w
```

### Deploy Application Changes

```bash
# Changes are auto-deployed via ArgoCD
git add .
git commit -m "Update application config"
git push

# Force sync if needed
argocd app sync <app-name>-prod
```

### Access ArgoCD UI

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access at: https://localhost:8080
# Username: admin
```

---

## 📁 Repository Structure

```
.
├── docs/                           # Documentation
│   ├── bootstrap/                  # Setup guides
│   │   └── 01-new-cluster-bootstrap.md
│   ├── operations/                 # Operational runbooks
│   │   ├── backup-restore.md
│   │   ├── disaster-recovery.md
│   │   └── troubleshooting.md
│   ├── architecture/               # Architecture docs
│   └── reference/                  # Reference materials
│
├── environments/                   # Terraform environments
│   ├── shared/                     # Core infrastructure
│   ├── dev/                        # Development
│   ├── qa/                         # QA/Staging
│   └── prod/                       # Production
│
├── modules/                        # Terraform modules
│   ├── argocd/                     # ArgoCD deployment
│   ├── cnpg-operator/              # PostgreSQL operator
│   ├── cnpg-cluster/               # Database clusters
│   ├── azure-kv/                   # Key Vault integration
│   └── azure-storage/              # Backup storage
│
├── apps/                           # Application manifests
│   └── {app}/
│       ├── base/                   # Base Kustomize configs
│       └── overlays/
│           ├── dev/
│           ├── qa/
│           └── prod/
│
├── databases/                      # Database manifests
│   └── {app}/
│       ├── base/                   # Base database configs
│       └── overlays/
│           ├── prod/
│           │   ├── cluster.yaml
│           │   ├── scheduled-backup.yaml
│           │   └── restore-from-azure.yaml
│           └── qa/
│
├── infrastructure/                 # Infrastructure components
│   ├── external-secrets/
│   ├── monitoring/
│   └── ingress/
│
├── argocd/                        # ArgoCD applications
│   └── applicationset.yaml        # Auto-discovery config
│
└── scripts/                       # Automation scripts
    ├── setup-microceph-k8s.sh
    └── dev-workflow.sh
```

---

## 🔐 Security

### Secrets Management

- **Azure Key Vault** stores all sensitive data
- **External Secrets Operator** syncs to Kubernetes
- **No secrets in Git** - all credentials external
- **Service Principal** with minimal permissions
- **SAS tokens** for Azure Storage access

### Access Control

- **RBAC** for Kubernetes resources
- **Network policies** for pod communication (optional)
- **TLS certificates** via cert-manager
- **Private container registry** support

---

## 🛡️ Disaster Recovery

### Recovery Objectives

| Metric | Target | Typical |
|--------|--------|---------|
| **RTO** (Recovery Time) | < 10 min | 3-5 min |
| **RPO** (Recovery Point) | < 5 min | 1-5 min |

### Backup Verification

All databases have:
- ✅ Daily scheduled backups at 01:00 UTC
- ✅ Continuous WAL archiving every 5 minutes
- ✅ Tested restore procedures
- ✅ 7-day retention policy

### Emergency Procedures

See **[Disaster Recovery Runbook](docs/operations/disaster-recovery.md)** for:
- Complete cluster loss recovery
- Single database restoration
- Azure storage access recovery
- Terraform state recovery

---

## 🤝 Contributing

### Making Changes

1. **Infrastructure**: Update Terraform modules, run `terraform plan`
2. **Applications**: Update Kustomize overlays, ArgoCD auto-syncs
3. **Databases**: Update cluster specs, test in dev first
4. **Documentation**: Keep docs up-to-date with changes

### Testing Changes

```bash
# Test Kustomize locally
kustomize build apps/{app}/overlays/prod/

# Dry-run apply
kubectl apply --dry-run=client -k apps/{app}/overlays/prod/

# Deploy to dev first
git push origin feature-branch
# ArgoCD syncs to dev automatically
```

---

## 📊 Monitoring

### Health Checks

```bash
# Overall system health
./scripts/health-check.sh

# Specific components
kubectl get pods -n argocd
kubectl get clusters -n cnpg-prod
kubectl get applications -n argocd
```

### Prometheus Metrics

Access Prometheus at: `http://<LoadBalancer-IP>:9090`

Key metrics:
- `cnpg_pg_database_size_bytes` - Database size
- `cnpg_pg_replication_lag` - Replication lag
- `argocd_app_sync_status` - Application sync status

---

## ❓ Support & Troubleshooting

### Quick Links

- **[Troubleshooting Guide](docs/operations/troubleshooting.md)** - Common issues
- **[Backup Procedures](docs/operations/backup-restore.md)** - Backup & restore
- **[Disaster Recovery](docs/operations/disaster-recovery.md)** - Emergency runbooks

### Common Issues

1. **Pods not starting**: Check `kubectl describe pod <name>`
2. **Database connection failures**: Verify service names and credentials
3. **ArgoCD not syncing**: Check application status and repo access
4. **Backups failing**: Verify Azure credentials and storage access

### Getting Help

1. Check documentation in `/docs`
2. Review application logs
3. Check ArgoCD UI for sync errors
4. Review recent Git commits
5. Consult troubleshooting guide

---

## 📝 License

This project is for personal homelab use. Modify as needed for your environment.

---

## 🙏 Acknowledgments

Built with:
- [MicroK8s](https://microk8s.io/) - Lightweight Kubernetes
- [ArgoCD](https://argoproj.github.io/cd/) - GitOps continuous delivery
- [CloudNative-PG](https://cloudnative-pg.io/) - PostgreSQL operator
- [External Secrets Operator](https://external-secrets.io/) - Secrets management
- [Terraform](https://www.terraform.io/) - Infrastructure as Code
- [Kustomize](https://kustomize.io/) - Kubernetes configuration management

---

**Documentation Status**: ✅ Complete and up-to-date as of 2025-10-08

For detailed procedures, see the `/docs` directory.
