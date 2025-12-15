# Gitea Deployment Guide

## Overview

Gitea is a lightweight, self-hosted Git service. This deployment provides:

- **Version**: Gitea 1.25
- **Database**: PostgreSQL via CloudNativePG (CNPG)
- **Namespace**: `gitea-prod` for application, `cnpg-prod` for database
- **Ingress**: `gitea.lab.aminrj.com` with Let's Encrypt TLS
- **SSH Access**: LoadBalancer service on port 22

## Architecture

```
┌─────────────────────────────────────────┐
│         gitea.lab.aminrj.com            │
│         (HTTPS + SSH Git Access)        │
└──────────────────┬──────────────────────┘
                   │
         ┌─────────▼──────────┐
         │  Nginx Ingress     │ (HTTP/HTTPS)
         │  + LoadBalancer    │ (SSH Port 22)
         └─────────┬──────────┘
                   │
         ┌─────────▼──────────┐
         │   Gitea Service    │
         │   (gitea-prod ns)  │
         └─────────┬──────────┘
                   │
         ┌─────────▼──────────┐
         │  Gitea Deployment  │
         │  - Replicas: 1     │
         │  - Image: 1.22.3   │
         │  - PVC: 20Gi       │
         └─────────┬──────────┘
                   │
         ┌─────────▼──────────┐
         │  PostgreSQL CNPG   │
         │  - Instances: 2    │
         │  - Storage: 20Gi   │
         │  - Daily Backups   │
         └────────────────────┘
```

## Deployment Steps

### 1. Apply Terraform Configuration

```bash
cd environments/prod
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

This creates:
- Azure Blob Storage container: `gitea-db-clean`
- Azure Key Vault secrets:
  - `gitea-db-username` = "gitea"
  - `gitea-db-name` = "gitea"
  - `gitea-db-password` (random)
  - `gitea-secret-key` (random)
  - `gitea-internal-token` (random)

### 2. Verify ArgoCD Sync

ArgoCD will automatically detect and sync both applications:

```bash
# Check application status
kubectl get applications -n argocd | grep gitea

# Expected output:
# gitea-prod              Synced   Healthy
# db-gitea-prod           Synced   Healthy
```

### 3. Monitor Deployment

```bash
# Watch database cluster initialization
kubectl get cluster gitea-db-cnpg-v1 -n cnpg-prod -w

# Watch application pods
kubectl get pods -n gitea-prod -w

# Check database ready status
kubectl get pods -n cnpg-prod -l cnpg.io/cluster=gitea-db-cnpg-v1
```

### 4. Verify Services

```bash
# Check HTTP service
kubectl get svc gitea-http -n gitea-prod

# Check SSH LoadBalancer (will get external IP)
kubectl get svc gitea-ssh -n gitea-prod

# Check ingress
kubectl get ingress -n gitea-prod
```

### 5. Access Gitea

**Web UI**: https://gitea.lab.aminrj.com

**Initial Setup**:
- First user to register becomes admin
- Database is pre-configured via environment variables
- No manual installation wizard needed

**SSH Git Access**:
```bash
# Get SSH service external IP
SSH_IP=$(kubectl get svc gitea-ssh -n gitea-prod -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Clone repository via SSH
git clone git@$SSH_IP:username/repository.git

# Or use domain (if DNS configured for SSH)
git clone git@gitea.lab.aminrj.com:username/repository.git
```

## Configuration

### Environment Variables

Key Gitea configurations (in `deployment.yaml`):

```yaml
GITEA__server__DOMAIN: gitea.lab.aminrj.com
GITEA__server__ROOT_URL: https://gitea.lab.aminrj.com
GITEA__service__DISABLE_REGISTRATION: "false"  # Change to "true" after admin setup
GITEA__service__REQUIRE_SIGNIN_VIEW: "false"   # Public or private instance
```

### Resource Allocation

**Application Pod**:
- Requests: 512Mi memory, 250m CPU
- Limits: 2Gi memory, 1000m CPU

**Database Cluster**:
- 2 instances (primary + replica)
- 512Mi-1Gi memory per instance
- 20Gi storage per instance

### Storage

**Application Data**: 20Gi PVC
- Git repositories: `/data/git/repositories`
- Attachments and uploads
- LFS objects

**Database**: 20Gi per instance
- PostgreSQL data
- WAL archives to Azure Blob

## Backup & Recovery

### Database Backups

**Scheduled Backups**:
- Daily at 1:00 AM UTC
- 7-day retention
- Stored in Azure: `gitea-db-clean` container
- WAL archiving for point-in-time recovery

**Manual Backup**:
```bash
kubectl cnpg backup gitea-db-cnpg-v1 \
  --backup-name gitea-manual-$(date +%Y%m%d) \
  -n cnpg-prod
```

**Check Backup Status**:
```bash
kubectl get backups -n cnpg-prod | grep gitea
kubectl get scheduledbackups -n cnpg-prod | grep gitea
```

### Application Data Backup

Git repositories are stored in PVC. Consider:

1. **Velero** for PVC snapshots
2. **Manual backup** via pod exec:
```bash
kubectl exec -n gitea-prod deploy/gitea -- tar czf - /data/git/repositories > gitea-repos-backup.tar.gz
```

## Monitoring

### Health Checks

```bash
# Application health
kubectl get pods -n gitea-prod
curl -k https://gitea.lab.aminrj.com/api/healthz

# Database health
kubectl get cluster gitea-db-cnpg-v1 -n cnpg-prod
kubectl cnpg status gitea-db-cnpg-v1 -n cnpg-prod
```

### Logs

```bash
# Application logs
kubectl logs -n gitea-prod deploy/gitea -f

# Database logs
kubectl logs -n cnpg-prod gitea-db-cnpg-v1-1 -f

# ArgoCD sync logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller | grep gitea
```

## Maintenance

### Update Gitea Version

Edit `apps/gitea/base/deployment.yaml`:
```yaml
image: gitea/gitea:1.23.0  # Update version
```

Commit and push - ArgoCD will auto-sync.

### Scale Database

Edit `databases/gitea/base/database.yaml`:
```yaml
spec:
  instances: 3  # Increase for read replicas
  storage:
    size: 50Gi  # Increase storage
```

### Disable User Registration

After creating admin account, edit overlay:
```yaml
- name: GITEA__service__DISABLE_REGISTRATION
  value: "true"
```

## Troubleshooting

### Database Connection Issues

```bash
# Check database service DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup gitea-db-cnpg-v1-rw.cnpg-prod.svc.cluster.local

# Check database credentials
kubectl get secret gitea-db-creds -n gitea-prod -o yaml
kubectl get secret gitea-db-creds -n cnpg-prod -o yaml

# Test database connection
kubectl exec -it gitea-db-cnpg-v1-1 -n cnpg-prod -- psql -U gitea -d gitea -c "SELECT version();"
```

### Application Not Starting

```bash
# Check pod events
kubectl describe pod -n gitea-prod -l app=gitea

# Check secret availability
kubectl get externalsecrets -n gitea-prod
kubectl get secrets -n gitea-prod

# Verify PVC binding
kubectl get pvc -n gitea-prod
```

### SSH Access Issues

```bash
# Check LoadBalancer service
kubectl get svc gitea-ssh -n gitea-prod

# Check if external IP assigned
kubectl describe svc gitea-ssh -n gitea-prod

# Test SSH connectivity
ssh -T git@<EXTERNAL_IP> -p 22
```

## Security Considerations

1. **Change default settings** after first login
2. **Disable registration** after admin setup
3. **Enable 2FA** for admin accounts
4. **Configure SSH keys** properly
5. **Regular security updates** - monitor Gitea releases
6. **Backup secrets** from Azure Key Vault
7. **Network policies** - consider adding to namespace

## Integration

### With CI/CD

Gitea provides:
- Webhooks for build triggers
- Actions (Gitea Actions - GitHub Actions compatible)
- API for automation

### With n8n

Create automation workflows:
- Auto-backup repositories
- Security scanning triggers
- Issue/PR notifications
- Repository statistics

### With Other Apps

- **Linkding**: Bookmark important repositories
- **Listmonk**: Notify team about releases
- **Threat Intel**: Store security tool configurations

## Resources

- **Official Docs**: https://docs.gitea.com/
- **Helm Chart Ref**: https://gitea.com/gitea/helm-chart
- **API Docs**: https://docs.gitea.com/api/1.22/
- **CNPG Docs**: https://cloudnative-pg.io/

## Quick Reference

```bash
# View all Gitea resources
kubectl get all -n gitea-prod

# Database cluster status
kubectl cnpg status gitea-db-cnpg-v1 -n cnpg-prod

# Check ingress
kubectl get ingress -n gitea-prod

# Restart application
kubectl rollout restart deployment/gitea -n gitea-prod

# Access Gitea pod shell
kubectl exec -it deploy/gitea -n gitea-prod -- /bin/sh

# Check backups
kubectl get backups -n cnpg-prod -l cnpg.io/cluster=gitea-db-cnpg-v1
```
