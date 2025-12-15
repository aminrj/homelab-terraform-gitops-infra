# Gitea Deployment - Quick Start

## ✅ What's Been Created

### Application Structure
```
app/gitea/
├── base/
│   ├── deployment.yaml      # Gitea 1.25 deployment
│   ├── service.yaml         # HTTP + SSH services
│   ├── pvc.yaml            # 20Gi storage for repos
│   └── kustomization.yaml
└── overlays/prod/
    ├── kustomization.yaml
    ├── namespace.yaml      # gitea-prod namespace
    ├── ingress.yaml        # gitea.lab.aminrj.com
    └── secrets.yaml        # ExternalSecrets from Azure KV
```

### Database Structure
```
databases/gitea/
├── base/
│   ├── database.yaml       # CNPG cluster: 2 instances, 20Gi each
│   └── kustomization.yaml
└── overlays/prod/
    ├── kustomization.yaml
    ├── scheduled-backup.yaml  # Daily 1 AM backups
    ├── secrets.yaml          # DB credentials + storage
    └── destination-path-patch.yaml
```

### Terraform Updates
- Added `gitea` to app storage containers
- Created `gitea_secrets` module with random passwords
- Configured Azure Blob Storage: `gitea-db-clean`

## 🚀 Deployment Steps

### 1. Apply Terraform (5 minutes)

```bash
cd environments/prod
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

### 2. Commit & Push to Git

```bash
git add .
git commit -m "Add Gitea deployment with PostgreSQL CNPG cluster"
git push origin main
```

### 3. ArgoCD Auto-Sync (2-3 minutes)

ArgoCD will automatically detect and deploy:
- `db-gitea-prod` - PostgreSQL cluster
- `gitea-prod` - Gitea application

Monitor:
```bash
# Watch ArgoCD applications
kubectl get applications -n argocd -w

# Watch database initialization
kubectl get cluster gitea-db-cnpg-v1 -n cnpg-prod -w

# Watch app deployment
kubectl get pods -n gitea-prod -w
```

### 4. Access Gitea

**URL**: https://gitea.lab.aminrj.com

**First Login**:
1. Wait for pods to be ready (~2-3 minutes)
2. Open https://gitea.lab.aminrj.com
3. Register first user (becomes admin automatically)
4. Start creating repositories!

## 🔧 Key Features

### High Availability
- **Database**: 2 PostgreSQL instances (primary + replica)
- **Automatic failover**: CNPG handles primary election
- **Daily backups**: 1 AM UTC to Azure Blob Storage
- **WAL archiving**: Point-in-time recovery capability

### Git Access
- **HTTPS**: https://gitea.lab.aminrj.com
- **SSH**: LoadBalancer service on port 22
- **LFS support**: Large file storage enabled
- **Webhooks**: Trigger CI/CD pipelines

### Security
- **TLS**: Let's Encrypt automatic certificates
- **Secrets**: Azure Key Vault integration
- **Isolation**: Dedicated namespace and network policies
- **Backup encryption**: Compressed and encrypted backups

## 📊 Resource Usage

| Component | Replicas | Memory | CPU | Storage |
|-----------|----------|--------|-----|---------|
| Gitea App | 1 | 512Mi-2Gi | 250m-1000m | 20Gi |
| PostgreSQL Primary | 1 | 512Mi-1Gi | 100m-500m | 20Gi |
| PostgreSQL Replica | 1 | 512Mi-1Gi | 100m-500m | 20Gi |

**Total**: ~5Gi memory, ~3 CPU cores, 60Gi storage

## 🔐 Security Best Practices

After first deployment:

1. **Disable public registration**:
   ```yaml
   # apps/gitea/base/deployment.yaml
   - name: GITEA__service__DISABLE_REGISTRATION
     value: "true"  # Change from "false"
   ```

2. **Enable 2FA** for admin account via Gitea UI

3. **Configure webhooks** with secret tokens

4. **Regular backups verification**:
   ```bash
   kubectl get backups -n cnpg-prod | grep gitea
   ```

## 🛠️ Common Operations

### Check Status
```bash
# Application
kubectl get pods -n gitea-prod
kubectl logs -n gitea-prod deploy/gitea -f

# Database
kubectl cnpg status gitea-db-cnpg-v1 -n cnpg-prod
kubectl get pods -n cnpg-prod -l cnpg.io/cluster=gitea-db-cnpg-v1
```

### Manual Backup
```bash
kubectl cnpg backup gitea-db-cnpg-v1 \
  --backup-name gitea-manual-$(date +%Y%m%d) \
  -n cnpg-prod
```

### Scale Database
```bash
# Edit databases/gitea/base/database.yaml
# Change instances: 3
# Commit and push - ArgoCD will sync
```

### Update Gitea Version
```bash
# Edit apps/gitea/base/deployment.yaml
# Change image: gitea/gitea:1.23.0
# Commit and push
```

## 🔍 Verification Checklist

- [ ] Terraform applied successfully
- [ ] Azure Key Vault secrets created
- [ ] ArgoCD applications synced
- [ ] Database cluster ready (2/2 pods)
- [ ] Gitea pod running
- [ ] Ingress configured with TLS
- [ ] SSH LoadBalancer has external IP
- [ ] Can access https://gitea.lab.aminrj.com
- [ ] First user registration works
- [ ] Can create a test repository
- [ ] SSH git clone works

## 📝 Next Steps

1. **Create your first repository** via web UI
2. **Configure SSH keys** in your user profile
3. **Test git operations**:
   ```bash
   git clone https://gitea.lab.aminrj.com/username/repo.git
   # or via SSH
   git clone git@gitea.lab.aminrj.com:username/repo.git
   ```
4. **Integrate with n8n** for automation workflows
5. **Set up webhooks** for CI/CD pipelines
6. **Configure organization/teams** for collaboration

## 🆘 Troubleshooting

### Gitea pod not starting
```bash
kubectl describe pod -n gitea-prod -l app=gitea
kubectl get externalsecrets -n gitea-prod
```

### Database connection issues
```bash
kubectl exec -it gitea-db-cnpg-v1-1 -n cnpg-prod -- \
  psql -U gitea -d gitea -c "SELECT 1;"
```

### TLS certificate not issued
```bash
kubectl get certificate -n gitea-prod
kubectl describe certificate gitea-tls -n gitea-prod
```

---

**Architecture Pattern**: ✅ Matches n8n, linkding, listmonk exactly
**Resilience**: ✅ HA database, automated backups, self-healing
**Efficiency**: ✅ Optimized resources, minimal overhead
**GitOps**: ✅ Full ArgoCD automation, declarative config
