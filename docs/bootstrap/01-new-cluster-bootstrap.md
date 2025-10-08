# Bootstrap New MicroK8s Cluster from Scratch

**Estimated Time**: 45-60 minutes
**Prerequisites**: Fresh MicroK8s installation, Azure subscription, Git access

---

## Overview

This guide walks through setting up a complete GitOps-managed Kubernetes homelab from scratch. By the end, you'll have:

- ✅ Multi-environment infrastructure (dev/qa/prod/shared)
- ✅ ArgoCD managing all deployments via GitOps
- ✅ PostgreSQL databases with automated backups to Azure
- ✅ Secrets management via Azure Key Vault
- ✅ SSL certificates via cert-manager
- ✅ Monitoring with Prometheus

---

## Phase 1: Prerequisites & Environment Setup

### 1.1 Install Required Tools

```bash
# Verify MicroK8s installation
microk8s status --wait-ready

# Install kubectl alias for MicroK8s
sudo snap alias microk8s.kubectl kubectl

# Verify Terraform (1.5+)
terraform version

# Verify Azure CLI
az version

# Install kubectl CNPG plugin (for database management)
curl -sSfL \
  https://github.com/cloudnative-pg/cloudnative-pg/raw/main/hack/install-cnpg-plugin.sh | \
  sudo sh -s -- -b /usr/local/bin
```

### 1.2 Enable MicroK8s Add-ons

```bash
# Enable required add-ons
microk8s enable dns
microk8s enable hostpath-storage
microk8s enable rbac

# Verify add-ons are running
microk8s status
```

### 1.3 Configure kubectl

```bash
# Export MicroK8s config
mkdir -p ~/.kube
microk8s config > ~/.kube/microk8s-config

# Set as default kubeconfig
export KUBECONFIG=~/.kube/microk8s-config

# Verify connectivity
kubectl get nodes
kubectl get pods -A
```

---

## Phase 2: Azure Resources Setup

### 2.1 Authenticate to Azure

```bash
# Login to Azure (use your tenant ID)
az logout
az login --tenant "YOUR-TENANT-ID" --scope "https://graph.microsoft.com/.default"

# Verify authentication
az account show

# Set subscription (if you have multiple)
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

### 2.2 Fork and Clone Repository

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/homelab-terraform-gitops-infra.git
cd homelab-terraform-gitops-infra

# Verify repository structure
ls -la
```

---

## Phase 3: Deploy Shared Infrastructure

The shared environment contains core components used by all other environments.

### 3.1 Configure Shared Environment

```bash
cd environments/shared

# Review and update terraform.tfvars with your settings
cat terraform.tfvars
```

### 3.2 Initialize and Deploy Shared

```bash
# Initialize Terraform
terraform init

# Export dummy Cloudflare token (required for validation)
export CLOUDFLARE_API_TOKEN="dummy-token-for-terraform-validation"

# Review planned changes
terraform plan -var-file="terraform.tfvars"

# Apply shared infrastructure
terraform apply -auto-approve
```

**Resources Created:**
- MetalLB load balancer
- cert-manager for SSL certificates
- nginx-ingress-controller
- External Secrets Operator
- Prometheus monitoring stack
- ArgoCD (GitOps controller)
- CloudNative-PG operator (PostgreSQL)

### 3.3 Verify Shared Deployment

```bash
# Check all shared namespaces
kubectl get namespaces

# Verify ArgoCD
kubectl get pods -n argocd
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Verify CNPG operator
kubectl get pods -n cnpg-system

# Verify External Secrets Operator
kubectl get pods -n external-secrets

# Verify cert-manager
kubectl get pods -n cert-manager

# Verify Prometheus stack
kubectl get pods -n monitoring
```

---

## Phase 4: Deploy Production Environment

### 4.1 Configure Production Environment

```bash
cd ../prod

# Review and update terraform.tfvars
# Ensure Azure resource names, storage accounts, and Key Vault names are correct
cat terraform.tfvars
```

### 4.2 Import Existing Azure Resources (if applicable)

If you have existing Azure storage containers from previous deployments:

```bash
# Initialize Terraform
terraform init

# Import existing storage containers
# Replace with your actual storage account name
STORAGE_ACCOUNT="homelabstorageaccntprod"

# Import app storage containers
terraform import 'module.app_storage["n8n"].azurerm_storage_container.app' \
  "https://${STORAGE_ACCOUNT}.blob.core.windows.net/n8n-db-clean"

terraform import 'module.app_storage["listmonk"].azurerm_storage_container.app' \
  "https://${STORAGE_ACCOUNT}.blob.core.windows.net/listmonk-db-clean"

terraform import 'module.app_storage["linkding"].azurerm_storage_container.app' \
  "https://${STORAGE_ACCOUNT}.blob.core.windows.net/linkding-db-clean"

terraform import 'module.app_storage["commafeed"].azurerm_storage_container.app' \
  "https://${STORAGE_ACCOUNT}.blob.core.windows.net/commafeed-db-clean"

terraform import 'module.app_storage["wallabag"].azurerm_storage_container.app' \
  "https://${STORAGE_ACCOUNT}.blob.core.windows.net/wallabag-db-clean"
```

### 4.3 Deploy Production Infrastructure

```bash
# Deploy production resources
terraform plan -var-file="terraform.tfvars"
terraform apply -auto-approve
```

**Resources Created:**
- Azure Key Vault with application secrets
- Azure Storage Account and containers for backups
- Service Principal for External Secrets Operator
- Database credentials stored in Key Vault
- Backup configurations for all applications

### 4.4 Configure External Secrets Operator

```bash
# Create namespace if not exists
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

# Create Azure credentials secret for External Secrets Operator
kubectl create secret generic azure-creds \
  -n external-secrets \
  --from-literal=client-id="$(terraform output -raw client_id)" \
  --from-literal=client-secret="$(terraform output -raw client_secret)"

# Verify secret creation
kubectl get secret azure-creds -n external-secrets
```

### 4.5 Verify Production Deployment

```bash
# Check ClusterSecretStore
kubectl get clustersecretstores
kubectl describe clustersecretstore azure-kv-store-prod

# Check ExternalSecrets are syncing
kubectl get externalsecrets -A
kubectl get secrets -A | grep -E "n8n|linkding|commafeed|wallabag|listmonk"

# Check ArgoCD applications
kubectl get applications -n argocd
```

---

## Phase 5: Deploy Applications via ArgoCD

### 5.1 Access ArgoCD UI

```bash
# Get ArgoCD admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"

# Get ArgoCD service (if LoadBalancer)
kubectl get svc argocd-server -n argocd

# Or port-forward to access locally
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Access ArgoCD at `https://localhost:8080` with:
- Username: `admin`
- Password: `<from above>`

### 5.2 Verify ArgoCD Auto-Discovery

ArgoCD uses ApplicationSets to automatically discover and deploy applications.

```bash
# Check ApplicationSets
kubectl get applicationsets -n argocd

# Check auto-discovered applications
kubectl get applications -n argocd

# Expected applications:
# - db-{app}-prod (database clusters)
# - {app}-prod (application deployments)
# - infra-{component}-prod (infrastructure components)
```

### 5.3 Sync Applications

```bash
# Install argocd CLI (optional but recommended)
# On Linux:
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login to ArgoCD
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

# Sync all applications
argocd app sync -l argocd.argoproj.io/instance

# Or sync individually
argocd app sync db-linkding-prod
argocd app sync linkding-prod
```

---

## Phase 6: Verify Complete Deployment

### 6.1 Check Database Clusters

```bash
# List all PostgreSQL clusters
kubectl get clusters -n cnpg-prod

# Check cluster health
kubectl cnpg status linkding-db-cnpg-v1 -n cnpg-prod
kubectl cnpg status commafeed-db-cnpg-v1 -n cnpg-prod
kubectl cnpg status wallabag-db-cnpg-v1 -n cnpg-prod
kubectl cnpg status n8n-db-cnpg-v1 -n cnpg-prod
kubectl cnpg status listmonk-db-cnpg-v1 -n cnpg-prod

# Verify backups are configured
kubectl get scheduledbackups -n cnpg-prod
```

### 6.2 Check Application Deployments

```bash
# Check all application pods
kubectl get pods -n linkding-prod
kubectl get pods -n commafeed-prod
kubectl get pods -n wallabag-prod
kubectl get pods -n n8n-prod
kubectl get pods -n listmonk-prod

# Check services and ingresses
kubectl get svc,ingress -A | grep -E "linkding|commafeed|wallabag|n8n|listmonk"
```

### 6.3 Verify Backup System

```bash
# Check WAL archiving for all databases
for cluster in linkding commafeed wallabag n8n listmonk; do
  echo "=== $cluster WAL archiving ==="
  kubectl logs ${cluster}-db-cnpg-v1-1 -n cnpg-prod --tail=5 | grep "Archived WAL"
done

# Verify scheduled backups
kubectl get scheduledbackups -n cnpg-prod

# Check recent backups
kubectl get backups -n cnpg-prod --sort-by=.metadata.creationTimestamp
```

---

## Phase 7: Post-Deployment Configuration

### 7.1 Configure DNS (if using custom domains)

```bash
# Get LoadBalancer IPs for ingress
kubectl get svc -n ingress-nginx

# Update your DNS records to point to the LoadBalancer IP
# Example:
# linkding.yourdomain.com -> <LoadBalancer-IP>
# commafeed.yourdomain.com -> <LoadBalancer-IP>
```

### 7.2 Configure SSL Certificates

```bash
# Verify cert-manager ClusterIssuers
kubectl get clusterissuers

# Check certificate status
kubectl get certificates -A
```

### 7.3 Set Up Monitoring Access

```bash
# Get Prometheus service
kubectl get svc -n monitoring

# Get Grafana service (if deployed)
kubectl get svc -n monitoring | grep grafana

# Port-forward Grafana (if needed)
kubectl port-forward svc/grafana -n monitoring 3000:3000
```

---

## Phase 8: Optional Environments

### 8.1 Deploy Dev Environment

```bash
cd environments/dev
terraform init
terraform apply -auto-approve
```

### 8.2 Deploy QA Environment

```bash
cd environments/qa
terraform init
terraform apply -auto-approve
```

---

## Validation Checklist

Before considering bootstrap complete, verify:

- [ ] All pods in `argocd` namespace are Running
- [ ] All pods in `cnpg-system` namespace are Running
- [ ] All pods in `external-secrets` namespace are Running
- [ ] All PostgreSQL clusters show "Cluster in healthy state"
- [ ] All ArgoCD applications show "Synced" and "Healthy"
- [ ] ExternalSecrets are syncing successfully
- [ ] At least one backup exists for each database
- [ ] WAL archiving is working for all databases
- [ ] Applications are accessible via ingress
- [ ] Monitoring stack is operational

---

## Next Steps

1. **Configure Backups**: Review `docs/operations/backup-restore.md`
2. **Set Up Monitoring**: Configure Prometheus alerts
3. **Review Security**: Audit RBAC and network policies
4. **Document Custom Config**: Record any environment-specific changes

---

## Troubleshooting Common Bootstrap Issues

### ArgoCD Applications Not Syncing

```bash
# Check ArgoCD application status
kubectl describe application <app-name> -n argocd

# Force sync
argocd app sync <app-name>

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### External Secrets Not Syncing

```bash
# Check ClusterSecretStore
kubectl describe clustersecretstore azure-kv-store-prod

# Check specific ExternalSecret
kubectl describe externalsecret <name> -n <namespace>

# Verify Azure credentials
kubectl get secret azure-creds -n external-secrets -o yaml
```

### Database Cluster Not Starting

```bash
# Check cluster status
kubectl get cluster <cluster-name> -n cnpg-prod -o yaml

# Check pod logs
kubectl logs <cluster-name>-1 -n cnpg-prod

# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

### Terraform State Issues

```bash
# If state is locked
terraform force-unlock <LOCK-ID>

# If resources already exist
terraform import <resource-address> <resource-id>
```

---

## Emergency Rollback

If bootstrap fails critically:

```bash
# Destroy production environment
cd environments/prod
terraform destroy -auto-approve

# Destroy shared environment
cd ../shared
terraform destroy -auto-approve

# Clean up Kubernetes resources
kubectl delete namespace argocd
kubectl delete namespace cnpg-system
kubectl delete namespace external-secrets
kubectl delete namespace monitoring

# Start over from Phase 3
```

---

**Bootstrap Complete!** Your GitOps homelab is now running. All changes to this repository will be automatically deployed via ArgoCD.
