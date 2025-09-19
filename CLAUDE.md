# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Kubernetes homelab infrastructure repository using GitOps with Terraform, ArgoCD, and Azure integration. It manages a MicroK8s cluster with various applications and infrastructure components across multiple environments (dev, qa, prod).

## High-Level Architecture

### Core Components
- **Terraform Modules**: Reusable infrastructure components in `/modules/`
- **Environment Management**: Multi-environment setup in `/environments/` (dev, qa, prod, shared)
- **GitOps with ArgoCD**: Automated deployment and synchronization
- **Azure Integration**: Key Vault for secrets, storage for backups
- **PostgreSQL with CNPG**: Cloud Native PostgreSQL operator for database management
- **Observability Stack**: Prometheus, monitoring, and alerting

### Directory Structure
```
├── environments/        # Environment-specific Terraform configurations
│   ├── dev/            # Development environment
│   ├── qa/             # QA environment
│   ├── prod/           # Production environment
│   └── shared/         # Shared resources
├── modules/            # Reusable Terraform modules
│   ├── argocd/         # ArgoCD GitOps setup
│   ├── cnpg-*/         # PostgreSQL operator and clusters
│   ├── azure-*/        # Azure Key Vault and storage integration
│   └── ...             # Other infrastructure modules
├── apps/               # Application Kustomize configurations
│   └── */overlays/     # Environment-specific app configs
├── databases/          # Database Kustomize configurations
├── infrastructure/     # Core infrastructure Kustomize configs
├── argocd/            # ArgoCD Application definitions
└── scripts/           # Automation and deployment scripts
```

### Key Architecture Patterns

1. **Multi-Environment**: Environment isolation with dev/qa/prod using Terraform workspaces and Kustomize overlays
2. **GitOps Flow**: ArgoCD watches this repository and auto-deploys changes to Kubernetes
3. **Secrets Management**: Azure Key Vault integration with External Secrets Operator
4. **Database Management**: PostgreSQL clusters managed by CloudNative-PG operator
5. **Backup Strategy**: Automated database backups to Azure storage with scheduled backup jobs
6. **Application Structure**: Kustomize base + overlays pattern for environment-specific configurations

### ArgoCD Integration
- **ApplicationSets**: Auto-discover apps and environments using directory generators
- **Self-Managed**: ArgoCD manages its own configuration through GitOps
- **App Pattern**: `apps/{app-name}/overlays/{environment}` automatically creates `{app-name}-{environment}` applications

## Common Development Commands

### Infrastructure Deployment
```bash
# Deploy to specific environment
cd environments/dev
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply

# Initialize External Secrets Operator
kubectl create ns external-secrets
kubectl create secret generic azure-creds \
  -n external-secrets \
  --from-literal=client-id="$(terraform output -raw client_id)" \
  --from-literal=client-secret="$(terraform output -raw client_secret)"
```

### Application Management
```bash
# Apply app changes directly (for testing)
kubectl apply -k apps/{app-name}/overlays/{environment}/

# Check ArgoCD sync status
kubectl get applications -n argocd

# Manual sync if needed
argocd app sync {app-name}-{environment}
```

### Database Operations
```bash
# Check PostgreSQL cluster status
kubectl get clusters -n cnpg-{environment}
kubectl get pods -n cnpg-{environment}

# Database backups
kubectl get scheduledbackups -n {app}-{environment}

# Restore from backup (see databases/*/overlays/*/restore-from-*.yaml)
kubectl apply -f databases/{app}/overlays/{environment}/restore-from-{source-env}.yaml
```

### Development Workflow Scripts
```bash
# Quick development setup
./scripts/dev-workflow.sh

# Full deployment with testing infrastructure
./scripts/deployment_script.sh

# Test LLM setup specifically
./scripts/test_llm_setup.sh

# Monitor performance
./scripts/monitor_llm_performance.sh
```

### Debugging and Troubleshooting
```bash
# Check all pods across namespaces
kubectl get pods --all-namespaces

# ArgoCD application status
kubectl get apps -n argocd -o wide

# Check External Secrets sync
kubectl get externalsecrets --all-namespaces
kubectl get secretstores --all-namespaces

# Database cluster health
kubectl cnpg status {cluster-name} -n {namespace}

# View application logs
kubectl logs -f deployment/{app-name} -n {namespace}
```

### Environment-Specific Notes

- **Dev Environment**: Single PostgreSQL instance, local-path storage, relaxed resource limits
- **QA Environment**: Production-like setup, scheduled backups, integration testing
- **Prod Environment**: HA PostgreSQL, persistent storage, strict resource limits, monitoring

### Key Configuration Files

- `environments/{env}/terraform.tfvars`: Environment-specific Terraform variables
- `argocd/applicationset.yaml`: Auto-discovery configuration for apps
- `modules/argocd/argocd-config.yaml`: ArgoCD self-management configuration
- `infrastructure/external-secrets/`: External Secrets configuration per environment

## Important Notes

- Changes to `/apps/`, `/databases/`, and `/infrastructure/` directories are automatically picked up by ArgoCD
- Database passwords and secrets are managed through Azure Key Vault and External Secrets Operator
- The repository uses a "base + overlays" pattern - modify base configurations in `/base/` directories and environment-specific overrides in `/overlays/{environment}/`
- All persistent data uses backup strategies - check `scheduled-backup.yaml` files in database overlays
- Resource limits and storage classes vary by environment - check individual overlay configurations