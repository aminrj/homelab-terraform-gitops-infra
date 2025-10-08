# Troubleshooting Guide

Quick reference for common issues and their solutions.

---

## Database Issues

### PostgreSQL Cluster Not Starting

**Symptoms**: Cluster stuck in "Waiting" or "Initializing" state

**Diagnosis**:
```bash
# Check cluster status
kubectl get cluster <cluster-name> -n cnpg-prod -o yaml

# Check pod status
kubectl get pods -n cnpg-prod | grep <cluster-name>

# Check pod logs
kubectl logs <cluster-name>-1 -n cnpg-prod

# Check operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg
```

**Common Causes & Solutions**:

1. **Storage Issues**
   ```bash
   # Check PVC status
   kubectl get pvc -n cnpg-prod

   # Check storage class
   kubectl get storageclass

   # Ensure local-path provisioner is running
   kubectl get pods -n kube-system | grep local-path
   ```

2. **Secret Not Found**
   ```bash
   # Check if database credentials exist
   kubectl get secret <app>-db-creds -n cnpg-prod

   # Verify ExternalSecret is synced
   kubectl get externalsecret <app>-db-creds -n cnpg-prod
   kubectl describe externalsecret <app>-db-creds -n cnpg-prod
   ```

3. **Image Pull Failures**
   ```bash
   # Check for ImagePullBackOff
   kubectl describe pod <cluster-name>-1 -n cnpg-prod | grep -A 5 Events

   # Verify image name in cluster spec
   kubectl get cluster <cluster-name> -n cnpg-prod -o jsonpath='{.spec.imageName}'
   ```

---

### Backup Failures

**Symptoms**: Scheduled backups failing, WAL archiving errors

**Diagnosis**:
```bash
# Check recent backups
kubectl get backups -n cnpg-prod --sort-by=.metadata.creationTimestamp

# Check specific backup
kubectl describe backup <backup-name> -n cnpg-prod

# Check cluster logs for backup errors
kubectl logs <cluster-name>-1 -n cnpg-prod | grep -i backup

# Check WAL archiving
kubectl logs <cluster-name>-1 -n cnpg-prod | grep -i "wal-archive"
```

**Common Causes & Solutions**:

1. **Azure Storage Credentials Invalid**
   ```bash
   # Check storage secret
   kubectl get secret <app>-db-storage -n cnpg-prod -o yaml

   # Verify ExternalSecret sync
   kubectl describe externalsecret <app>-db-storage -n cnpg-prod

   # Test Azure connectivity from pod
   kubectl exec <cluster-name>-1 -n cnpg-prod -- \
     curl -I https://homelabstorageaccntprod.blob.core.windows.net
   ```

2. **Storage Path Issues**
   ```bash
   # Verify destinationPath in cluster spec
   kubectl get cluster <cluster-name> -n cnpg-prod -o yaml | grep destinationPath

   # Should be: https://homelabstorageaccntprod.blob.core.windows.net/<app>-db-clean
   ```

3. **SAS Token Expired**
   ```bash
   # Rotate SAS token in Azure Key Vault
   # Then force secret refresh
   kubectl delete pod <cluster-name>-1 -n cnpg-prod
   ```

---

### Database Connection Failures

**Symptoms**: Applications can't connect to database

**Diagnosis**:
```bash
# Check if database is running
kubectl get cluster <cluster-name> -n cnpg-prod

# Test connectivity from within cluster
kubectl run -it --rm debug --image=postgres:16 --restart=Never -- \
  psql -h <cluster-name>-rw.cnpg-prod.svc.cluster.local -U postgres -d <database-name>

# Check service endpoints
kubectl get svc -n cnpg-prod | grep <cluster-name>
kubectl get endpoints -n cnpg-prod | grep <cluster-name>
```

**Common Causes & Solutions**:

1. **Wrong Service Name**
   ```bash
   # Use read-write service for applications:
   <cluster-name>-rw.cnpg-prod.svc.cluster.local:5432

   # NOT the individual pod service
   ```

2. **Wrong Credentials**
   ```bash
   # Check credentials in secret
   kubectl get secret <app>-db-creds -n cnpg-prod -o jsonpath='{.data.POSTGRES_USER}' | base64 -d
   kubectl get secret <app>-db-creds -n cnpg-prod -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d

   # Verify application is using same credentials
   kubectl get deployment <app> -n <app>-prod -o yaml | grep -A 5 "env:"
   ```

3. **Network Policy Blocking**
   ```bash
   # Check network policies
   kubectl get networkpolicies -A

   # Test from application pod
   kubectl exec <app-pod> -n <app>-prod -- nc -zv <cluster-name>-rw.cnpg-prod.svc.cluster.local 5432
   ```

---

## Application Issues

### Pod CrashLoopBackOff

**Symptoms**: Application pod keeps restarting

**Diagnosis**:
```bash
# Check pod status
kubectl get pods -n <namespace>

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check logs from current container
kubectl logs <pod-name> -n <namespace>

# Check logs from previous crash
kubectl logs <pod-name> -n <namespace> --previous
```

**Common Causes & Solutions**:

1. **Liveness Probe Failure**
   ```bash
   # Check probe configuration
   kubectl get deployment <app> -n <namespace> -o yaml | grep -A 10 livenessProbe

   # Example fix (commafeed issue)
   # Change probe path from /q/health/live to /
   ```

2. **Database Not Ready**
   ```bash
   # Ensure database is ready before starting app
   # Add initContainer to wait for database
   ```

3. **Missing Environment Variables**
   ```bash
   # Check required environment variables
   kubectl get deployment <app> -n <namespace> -o yaml | grep -A 20 "env:"

   # Verify secrets are populated
   kubectl get secret <secret-name> -n <namespace>
   ```

---

### Application Not Accessible

**Symptoms**: Can't access application via ingress or service

**Diagnosis**:
```bash
# Check pod status
kubectl get pods -n <namespace>

# Check service
kubectl get svc -n <namespace>

# Check ingress
kubectl get ingress -n <namespace>
kubectl describe ingress <ingress-name> -n <namespace>

# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

**Common Causes & Solutions**:

1. **Service Not Routing to Pods**
   ```bash
   # Check endpoints
   kubectl get endpoints <service-name> -n <namespace>

   # If empty, check pod labels match service selector
   kubectl get pods -n <namespace> --show-labels
   kubectl get svc <service-name> -n <namespace> -o yaml | grep selector
   ```

2. **Ingress Not Configured**
   ```bash
   # Check ingress class
   kubectl get ingress <ingress-name> -n <namespace> -o yaml | grep ingressClassName

   # Verify cert-manager certificate
   kubectl get certificate -n <namespace>
   kubectl describe certificate <cert-name> -n <namespace>
   ```

3. **DNS Not Resolving**
   ```bash
   # Test DNS from within cluster
   kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <app>.yourdomain.com

   # Check external-dns logs (if using)
   kubectl logs -n kube-system -l app=external-dns
   ```

---

## ArgoCD Issues

### Applications Not Syncing

**Symptoms**: ArgoCD shows "OutOfSync" status

**Diagnosis**:
```bash
# Check application status
kubectl get applications -n argocd

# Check specific application
kubectl describe application <app-name> -n argocd

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Check repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
```

**Common Causes & Solutions**:

1. **Manual Changes in Cluster**
   ```bash
   # View diff
   argocd app diff <app-name>

   # Force sync to overwrite manual changes
   argocd app sync <app-name> --force

   # Or enable auto-sync in application
   kubectl patch application <app-name> -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":{}}}}'
   ```

2. **Invalid Kustomization**
   ```bash
   # Test kustomization locally
   kustomize build apps/<app>/overlays/prod/

   # Check for YAML syntax errors
   kubectl apply --dry-run=client -k apps/<app>/overlays/prod/
   ```

3. **Git Repository Access Issues**
   ```bash
   # Check repository secret
   kubectl get secret -n argocd | grep repo

   # Re-add repository
   argocd repo add <repo-url> --name <name>
   ```

---

### ArgoCD Server Not Accessible

**Symptoms**: Can't access ArgoCD UI

**Diagnosis**:
```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check ArgoCD server service
kubectl get svc argocd-server -n argocd

# Check ingress (if configured)
kubectl get ingress -n argocd
```

**Common Causes & Solutions**:

1. **Port-Forward Not Working**
   ```bash
   # Kill existing port-forward
   killall kubectl

   # Start new port-forward
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```

2. **LoadBalancer Not Assigned**
   ```bash
   # Check MetalLB status
   kubectl get pods -n metallb-system

   # Check IP pool
   kubectl get ipaddresspool -n metallb-system

   # Check service type
   kubectl get svc argocd-server -n argocd -o yaml | grep type
   ```

---

## External Secrets Issues

### Secrets Not Syncing

**Symptoms**: ExternalSecret shows "SecretSyncedError"

**Diagnosis**:
```bash
# Check ExternalSecret status
kubectl get externalsecret <name> -n <namespace>
kubectl describe externalsecret <name> -n <namespace>

# Check ClusterSecretStore
kubectl describe clustersecretstore azure-kv-store-prod

# Check operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

**Common Causes & Solutions**:

1. **Azure Credentials Invalid**
   ```bash
   # Check azure-creds secret
   kubectl get secret azure-creds -n external-secrets -o yaml

   # Recreate with fresh credentials
   cd environments/prod
   kubectl create secret generic azure-creds \
     -n external-secrets \
     --from-literal=client-id="$(terraform output -raw client_id)" \
     --from-literal=client-secret="$(terraform output -raw client_secret)" \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

2. **Secret Not in Key Vault**
   ```bash
   # List secrets in Key Vault
   az keyvault secret list --vault-name <keyvault-name>

   # Check specific secret
   az keyvault secret show --vault-name <keyvault-name> --name <secret-name>
   ```

3. **Wrong Secret Path**
   ```bash
   # Check ExternalSecret spec
   kubectl get externalsecret <name> -n <namespace> -o yaml | grep -A 5 remoteRef

   # Ensure path matches Key Vault secret name exactly
   ```

---

## Terraform Issues

### State Lock Errors

**Symptoms**: `Error: Error acquiring the state lock`

**Solutions**:
```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK-ID>

# Or wait for lock to expire (usually 10-15 minutes)
```

---

### Provider Authentication Failures

**Symptoms**: `Error: building AzureRM Client: obtain subscription`

**Solutions**:
```bash
# Re-authenticate to Azure
az logout
az login --tenant "<TENANT-ID>"

# Verify subscription
az account show

# Set subscription
az account set --subscription "<SUBSCRIPTION-ID>"

# Clear Terraform cache
rm -rf .terraform
terraform init
```

---

### Resource Already Exists

**Symptoms**: `Error: A resource with the ID already exists`

**Solutions**:
```bash
# Import existing resource
terraform import <resource-address> <resource-id>

# Example for storage container
terraform import 'module.app_storage["linkding"].azurerm_storage_container.app' \
  "https://homelabstorageaccntprod.blob.core.windows.net/linkding-db-clean"

# Or remove from state and re-import
terraform state rm <resource-address>
terraform import <resource-address> <resource-id>
```

---

## Kubernetes Issues

### Node NotReady

**Symptoms**: Node shows "NotReady" status

**Diagnosis**:
```bash
# Check node status
kubectl get nodes

# Check node conditions
kubectl describe node <node-name>

# Check kubelet logs
microk8s kubectl logs -n kube-system -l component=kubelet
```

**Solutions**:
```bash
# Restart MicroK8s
microk8s stop
microk8s start

# Check system resources
df -h
free -h
```

---

### Pod Pending (No Resources)

**Symptoms**: Pod stuck in "Pending" with "Insufficient cpu/memory"

**Solutions**:
```bash
# Check node resources
kubectl top nodes

# Check pod resource requests
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Requests:"

# Reduce resource requests or add nodes
```

---

### Storage Issues

**Symptoms**: PVC stuck in "Pending"

**Diagnosis**:
```bash
# Check PVC status
kubectl get pvc -A

# Check storage class
kubectl get storageclass

# Check provisioner
kubectl get pods -n kube-system | grep local-path
```

**Solutions**:
```bash
# Restart local-path provisioner
kubectl rollout restart deployment local-path-provisioner -n kube-system

# Check node disk space
df -h /var/snap/microk8s/common/default-storage
```

---

## Monitoring & Debugging Commands

### Quick Health Check

```bash
#!/bin/bash
# health-check.sh

echo "=== Nodes ==="
kubectl get nodes

echo "=== System Pods ==="
kubectl get pods -n kube-system | grep -v Running

echo "=== ArgoCD ==="
kubectl get pods -n argocd | grep -v Running
kubectl get applications -n argocd | grep -v "Synced.*Healthy"

echo "=== Databases ==="
kubectl get clusters -n cnpg-prod

echo "=== External Secrets ==="
kubectl get externalsecrets -A | grep -v SYNCED

echo "=== Applications ==="
for ns in linkding-prod commafeed-prod wallabag-prod n8n-prod listmonk-prod; do
  echo "--- $ns ---"
  kubectl get pods -n $ns | grep -v Running
done
```

### Common kubectl Commands

```bash
# Get all resources in namespace
kubectl get all -n <namespace>

# Describe resource with events
kubectl describe <resource-type> <name> -n <namespace>

# Follow logs
kubectl logs -f <pod-name> -n <namespace>

# Previous container logs
kubectl logs <pod-name> -n <namespace> --previous

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Port-forward service
kubectl port-forward svc/<service-name> -n <namespace> <local-port>:<remote-port>

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

---

## Escalation Path

1. **Check this guide** for common issues
2. **Review logs** from affected components
3. **Check recent changes** in Git history
4. **Review ArgoCD** application status
5. **Check Azure portal** for service health
6. **Consult documentation** in `/docs` folder
7. **Check CNPG operator** documentation
8. **Review Kubernetes events** system-wide

---

**Last Updated**: 2025-10-08
**Maintained By**: Homelab operations team
