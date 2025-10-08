# Disaster Recovery Runbook

**Purpose**: Step-by-step procedures for recovering from catastrophic failures.

---

## Disaster Scenarios & Response

### Scenario 1: Complete Cluster Loss

**Situation**: MicroK8s cluster completely destroyed, nodes unrecoverable

**Recovery Steps**: Follow bootstrap guide with database restoration

**Estimated Recovery Time**: 60-90 minutes

#### Recovery Procedure

1. **Rebuild MicroK8s Cluster** (15 minutes)
   ```bash
   # Install MicroK8s on new nodes
   sudo snap install microk8s --classic --channel=1.28/stable

   # Enable required add-ons
   microk8s enable dns hostpath-storage rbac

   # Configure kubectl
   microk8s config > ~/.kube/microk8s-config
   export KUBECONFIG=~/.kube/microk8s-config
   ```

2. **Restore Infrastructure** (30 minutes)
   ```bash
   # Clone repository
   git clone <your-repo-url>
   cd homelab-terraform-gitops-infra

   # Deploy shared environment
   cd environments/shared
   terraform init
   terraform apply -auto-approve

   # Deploy production environment
   cd ../prod
   terraform init
   terraform apply -auto-approve
   ```

3. **Configure External Secrets** (5 minutes)
   ```bash
   cd environments/prod
   kubectl create namespace external-secrets
   kubectl create secret generic azure-creds \
     -n external-secrets \
     --from-literal=client-id="$(terraform output -raw client_id)" \
     --from-literal=client-secret="$(terraform output -raw client_secret)"
   ```

4. **Restore Databases** (30 minutes)
   ```bash
   # For each application, create restore cluster
   for app in linkding commafeed wallabag n8n listmonk; do
     kubectl apply -f databases/${app}/overlays/prod/restore-from-azure.yaml
     echo "Waiting for ${app} restore..."
     sleep 60
   done

   # Verify all restores
   kubectl get clusters -n cnpg-prod
   ```

5. **Verify ArgoCD Sync** (10 minutes)
   ```bash
   # Wait for ArgoCD to deploy applications
   kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

   # Sync all applications
   argocd app sync -l argocd.argoproj.io/instance

   # Verify applications
   kubectl get applications -n argocd
   ```

---

### Scenario 2: Single Database Cluster Failure

**Situation**: One PostgreSQL cluster corrupted or lost

**Recovery Steps**: Restore specific database from Azure backup

**Estimated Recovery Time**: 5-10 minutes

#### Recovery Procedure

1. **Identify Failed Cluster**
   ```bash
   # Check cluster status
   kubectl get clusters -n cnpg-prod

   # Check pod status
   kubectl get pods -n cnpg-prod

   # Review logs
   kubectl logs <cluster-name>-1 -n cnpg-prod --tail=100
   ```

2. **Create Restore Cluster**
   ```bash
   # Use pre-configured restore file
   kubectl apply -f databases/<app-name>/overlays/prod/restore-from-azure.yaml

   # Or create custom restore
   cat > restore-emergency.yaml <<EOF
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: <app>-db-cnpg-v1-restore
     namespace: cnpg-prod
   spec:
     bootstrap:
       recovery:
         source: clusterBackup
         # Add recoveryTarget for PITR if needed
   # ... (see backup-restore.md for full config)
   EOF

   kubectl apply -f restore-emergency.yaml
   ```

3. **Update Application**
   ```bash
   # Update deployment to use restored database
   # New service: <app>-db-cnpg-v1-restore-rw.cnpg-prod.svc.cluster.local

   kubectl set env deployment/<app> -n <app>-prod \
     DATABASE_URL="postgresql://<user>:<pass>@<app>-db-cnpg-v1-restore-rw.cnpg-prod.svc.cluster.local:5432/<db>"
   ```

4. **Verify Application**
   ```bash
   # Check pods
   kubectl get pods -n <app>-prod

   # Test application
   curl http://<app-service>/health
   ```

---

### Scenario 3: Azure Storage Access Loss

**Situation**: Cannot access Azure Blob Storage (credentials expired, network issues)

**Recovery Steps**: Restore Azure credentials and connectivity

**Estimated Recovery Time**: 15-30 minutes

#### Recovery Procedure

1. **Verify Azure Access**
   ```bash
   # Re-authenticate to Azure
   az logout
   az login --tenant "<TENANT-ID>"

   # Test storage access
   az storage blob list \
     --account-name homelabstorageaccntprod \
     --container-name linkding-db-clean \
     --auth-mode login
   ```

2. **Rotate Service Principal Credentials**
   ```bash
   cd environments/prod

   # Get service principal app-id
   SP_APP_ID=$(terraform output -raw client_id)

   # Create new secret
   NEW_SECRET=$(az ad sp credential reset \
     --id $SP_APP_ID \
     --query password -o tsv)

   # Update Kubernetes secret
   kubectl create secret generic azure-creds \
     -n external-secrets \
     --from-literal=client-id="$SP_APP_ID" \
     --from-literal=client-secret="$NEW_SECRET" \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

3. **Verify External Secrets Sync**
   ```bash
   # Check ClusterSecretStore
   kubectl describe clustersecretstore azure-kv-store-prod

   # Verify secrets are syncing
   kubectl get externalsecrets -A
   ```

4. **Test Database Backup**
   ```bash
   # Create test backup
   kubectl cnpg backup linkding-db-cnpg-v1 \
     --backup-name linkding-connectivity-test \
     -n cnpg-prod

   # Verify backup succeeds
   kubectl get backup linkding-connectivity-test -n cnpg-prod -w
   ```

---

### Scenario 4: ArgoCD Failure

**Situation**: ArgoCD not syncing, applications out of date

**Recovery Steps**: Restore ArgoCD or manual application deployment

**Estimated Recovery Time**: 20-40 minutes

#### Recovery Procedure

**Option A: Reinstall ArgoCD**

```bash
# Remove existing ArgoCD
kubectl delete namespace argocd

# Redeploy via Terraform
cd environments/shared
terraform apply -target=module.argocd -auto-approve

# Recreate applications
kubectl apply -f argocd/applicationset.yaml
```

**Option B: Manual Application Deployment**

```bash
# Deploy applications directly with Kustomize
kubectl apply -k apps/linkding/overlays/prod/
kubectl apply -k apps/commafeed/overlays/prod/
kubectl apply -k apps/wallabag/overlays/prod/
kubectl apply -k apps/n8n/overlays/prod/
kubectl apply -k apps/listmonk/overlays/prod/

# Deploy databases
kubectl apply -k databases/linkding/overlays/prod/
kubectl apply -k databases/commafeed/overlays/prod/
kubectl apply -k databases/wallabag/overlays/prod/
kubectl apply -k databases/n8n/overlays/prod/
kubectl apply -k databases/listmonk/overlays/prod/
```

---

### Scenario 5: Terraform State Corruption

**Situation**: Terraform state file corrupted or lost

**Recovery Steps**: Rebuild state via import or restore from backup

**Estimated Recovery Time**: 30-60 minutes

#### Recovery Procedure

**Option A: Import Existing Resources**

```bash
cd environments/prod

# Import key resources
terraform import module.azure_kv.azurerm_key_vault.kv \
  "/subscriptions/<SUB-ID>/resourceGroups/<RG>/providers/Microsoft.KeyVault/vaults/<KV-NAME>"

terraform import 'module.app_storage["linkding"].azurerm_storage_container.app' \
  "https://homelabstorageaccntprod.blob.core.windows.net/linkding-db-clean"

# Repeat for all critical resources
```

**Option B: Restore State from Backup**

```bash
# If using remote state with versioning
terraform state pull > current-state.tfstate

# Restore from backup
cp terraform.tfstate.backup terraform.tfstate

# Verify state
terraform plan
```

**Option C: Rebuild State from Scratch**

```bash
# Remove state
rm terraform.tfstate

# Re-import all resources (tedious but complete)
# See bootstrap documentation for import commands
```

---

### Scenario 6: All Databases Corrupted

**Situation**: Data corruption affecting all databases

**Recovery Steps**: Mass restore from Azure backups

**Estimated Recovery Time**: 30-45 minutes

#### Recovery Procedure

1. **Identify Corruption Scope**
   ```bash
   # Check all cluster statuses
   kubectl get clusters -n cnpg-prod

   # Check for errors
   for cluster in linkding commafeed wallabag n8n listmonk; do
     echo "=== $cluster ==="
     kubectl logs ${cluster}-db-cnpg-v1-1 -n cnpg-prod --tail=20 | grep -i error
   done
   ```

2. **Stop All Applications**
   ```bash
   # Scale down applications to prevent further writes
   kubectl scale deployment --all --replicas=0 -n linkding-prod
   kubectl scale deployment --all --replicas=0 -n commafeed-prod
   kubectl scale deployment --all --replicas=0 -n wallabag-prod
   kubectl scale deployment --all --replicas=0 -n n8n-prod
   kubectl scale deployment --all --replicas=0 -n listmonk-prod
   ```

3. **Restore All Databases in Parallel**
   ```bash
   # Apply all restore configurations
   for app in linkding commafeed wallabag n8n listmonk; do
     kubectl apply -f databases/${app}/overlays/prod/restore-from-azure.yaml &
   done

   wait
   echo "All restore operations started"
   ```

4. **Monitor Restore Progress**
   ```bash
   # Watch all restore clusters
   watch -n 5 'kubectl get clusters -n cnpg-prod | grep restore'

   # Check individual restore logs
   for app in linkding commafeed wallabag n8n listmonk; do
     echo "=== $app restore ==="
     kubectl logs ${app}-db-cnpg-v1-restore-1 -n cnpg-prod --tail=5
   done
   ```

5. **Update All Applications**
   ```bash
   # Update database connections (via Kustomize or environment variables)
   # Point each app to: <app>-db-cnpg-v1-restore-rw.cnpg-prod.svc.cluster.local

   # Scale applications back up
   kubectl scale deployment --all --replicas=1 -n linkding-prod
   kubectl scale deployment --all --replicas=1 -n commafeed-prod
   kubectl scale deployment --all --replicas=1 -n wallabag-prod
   kubectl scale deployment --all --replicas=1 -n n8n-prod
   kubectl scale deployment --all --replicas=1 -n listmonk-prod
   ```

---

## Emergency Response Checklist

### Immediate Actions (First 5 Minutes)

- [ ] Identify scope of disaster (single app, multiple, cluster-wide)
- [ ] Stop affected applications to prevent data corruption
- [ ] Document error messages and failure symptoms
- [ ] Check Azure portal for service health issues
- [ ] Verify network connectivity to cluster and Azure

### Assessment Phase (5-15 Minutes)

- [ ] Check backup status and last successful backup time
- [ ] Verify Azure storage accessibility
- [ ] Review recent changes in Git history
- [ ] Check ArgoCD application status
- [ ] Review Prometheus alerts (if available)

### Recovery Phase (15-60 Minutes)

- [ ] Execute appropriate scenario recovery procedure
- [ ] Monitor restore/recovery progress
- [ ] Validate data integrity after recovery
- [ ] Test application functionality
- [ ] Document what happened and lessons learned

### Post-Recovery (After Service Restored)

- [ ] Verify all backups are running successfully
- [ ] Update monitoring/alerting if gaps identified
- [ ] Schedule post-mortem review
- [ ] Update disaster recovery procedures if needed
- [ ] Test recovered services under load

---

## Critical Contact Information

### Service Accounts

- **Azure Tenant ID**: `<stored in terraform.tfvars>`
- **Azure Subscription**: `<stored in terraform.tfvars>`
- **Service Principal**: `<output from terraform>`
- **Storage Account**: `homelabstorageaccntprod`
- **Key Vault**: `<from terraform output>`

### Repository Locations

- **Main Repository**: `<your-git-repo-url>`
- **Backup Repository**: `<optional-backup-location>`
- **Documentation**: `/docs` directory

### External Dependencies

- **Azure Blob Storage**: Backup storage
- **Azure Key Vault**: Secrets management
- **GitHub/GitLab**: GitOps source of truth

---

## Communication Plan

### Internal Stakeholders

1. **Identify impact**: Which services are down?
2. **Estimate recovery time**: Based on scenario
3. **Provide updates**: Every 15 minutes during recovery
4. **Document resolution**: Update status when complete

### Status Page Template

```
🔴 INCIDENT: [Service Name] Database Failure

Status: INVESTIGATING / RECOVERING / RESOLVED
Started: [Timestamp]
Impact: [List affected services]
Recovery ETA: [Based on scenario]

Updates:
- [Timestamp]: [Status update]
- [Timestamp]: [Status update]

Resolution: [Final resolution details]
```

---

## Prevention Measures

### Daily Monitoring

```bash
# Check backup health
kubectl get backups -n cnpg-prod --sort-by=.metadata.creationTimestamp | tail -10

# Verify WAL archiving
for cluster in linkding commafeed wallabag n8n listmonk; do
  kubectl logs ${cluster}-db-cnpg-v1-1 -n cnpg-prod --tail=5 | grep "Archived WAL"
done

# Check cluster health
kubectl get clusters -n cnpg-prod
```

### Weekly Tasks

- [ ] Test restore procedure for one database
- [ ] Review ArgoCD application sync status
- [ ] Verify Azure storage usage and retention
- [ ] Check for Kubernetes security updates
- [ ] Review and rotate credentials if needed

### Monthly Tasks

- [ ] Full disaster recovery drill
- [ ] Review and update documentation
- [ ] Audit Azure permissions and access
- [ ] Check backup storage costs
- [ ] Update Terraform modules and providers

---

## Recovery Validation Tests

After any disaster recovery, run these validation tests:

```bash
#!/bin/bash
# validate-recovery.sh

echo "=== Cluster Health ==="
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

echo "=== Database Health ==="
kubectl get clusters -n cnpg-prod

echo "=== Application Health ==="
for ns in linkding-prod commafeed-prod wallabag-prod n8n-prod listmonk-prod; do
  echo "Checking $ns..."
  kubectl get pods -n $ns
done

echo "=== Backup System ==="
kubectl get scheduledbackups -n cnpg-prod
kubectl get backups -n cnpg-prod --sort-by=.metadata.creationTimestamp | tail -5

echo "=== External Secrets ==="
kubectl get externalsecrets -A | grep -v SYNCED

echo "=== ArgoCD Applications ==="
kubectl get applications -n argocd | grep -v "Synced.*Healthy"

echo "=== Validation Complete ==="
```

---

## Lessons Learned Template

After each disaster recovery, document:

### Incident Summary
- **Date/Time**:
- **Detected By**:
- **Severity**:
- **Services Affected**:

### Timeline
- **Detection**:
- **Response Started**:
- **Service Restored**:
- **Total Downtime**:

### Root Cause
- **What Happened**:
- **Why It Happened**:
- **Contributing Factors**:

### Response Effectiveness
- **What Worked Well**:
- **What Didn't Work**:
- **Documentation Gaps**:

### Action Items
- [ ] Update procedures
- [ ] Improve monitoring
- [ ] Add automation
- [ ] Update documentation

---

**Last Updated**: 2025-10-08
**Next Review**: After each DR drill or actual incident
