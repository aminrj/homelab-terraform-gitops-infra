# Production Deployment Guide

## Prerequisites

1. MicroK8s cluster with rbd addon enabled
2. MicroCeph configured on the cluster
3. kubectl configured with microk8s-config

## Step 1: Configure MicroCeph Storage

Run this on one of your MicroK8s nodes:

```bash
./scripts/setup-microceph-k8s.sh
```

This will output the Ceph monitors and admin key. Update the following file with these values:
- `infrastructure/microceph-storage/overlays/prod/ceph-secret-patch.yaml`

Or apply the generated configuration directly:

```bash
kubectl apply -f /tmp/ceph-secret.yaml
```

## Step 2: Deploy Storage Configuration

```bash
kubectl apply -k infrastructure/microceph-storage/overlays/prod/
```

Verify the storage class is created and set as default:

```bash
kubectl get storageclass
```

## Step 3: Deploy Core Infrastructure with Terraform

Deploy the production environment:

```bash
cd environments/prod
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

This will deploy:
- ArgoCD (GitOps controller)
- External Secrets Operator (Azure Key Vault integration)
- CloudNativePG Operator (PostgreSQL management)
- Core infrastructure components

## Step 4: Configure External Secrets

Get the Azure credentials from Terraform outputs:

```bash
kubectl create secret generic azure-creds \
  -n external-secrets \
  --from-literal=client-id="$(terraform output -raw client_id)" \
  --from-literal=client-secret="$(terraform output -raw client_secret)"
```

## Step 5: Verify Deployment

Check that all core infrastructure is running:

```bash
# Check ArgoCD
kubectl get pods -n argocd

# Check External Secrets
kubectl get pods -n external-secrets

# Check CNPG
kubectl get pods -n cnpg-system

# Check ArgoCD Applications
kubectl get applications -n argocd
```

## Step 6: Access ArgoCD UI

Get the ArgoCD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Port-forward to access the UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then access https://localhost:8080 with username `admin` and the password from above.

## Troubleshooting

### Storage Issues

Check MicroCeph status:
```bash
microk8s ceph status
```

Check RBD provisioner:
```bash
kubectl get pods -n rook-ceph
kubectl logs -n rook-ceph -l app=csi-rbdplugin
```

### ArgoCD Sync Issues

Check application status:
```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
```

Force sync an application:
```bash
argocd app sync <app-name>
```

### Database Issues

Check PostgreSQL cluster status:
```bash
kubectl get clusters -n cnpg-prod
kubectl cnpg status <cluster-name> -n <namespace>
```
