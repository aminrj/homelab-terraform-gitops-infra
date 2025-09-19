# Infrastructure Review & Improvement Recommendations

**Review Date**: September 19, 2025
**Reviewer**: Claude Code Infrastructure Analysis
**Scope**: Complete homelab infrastructure repository audit

## Executive Summary

Your homelab infrastructure demonstrates solid GitOps patterns and multi-environment support. However, several critical issues were identified that impact reliability, security, and maintainability. This review provides 23 prioritized recommendations across 7 categories.

**Priority Summary**:
- 🚨 **Critical**: 5 issues requiring immediate attention
- ⚠️ **High**: 8 issues affecting reliability and security
- 📋 **Medium**: 7 optimizations for maintainability
- 💡 **Low**: 3 nice-to-have improvements

---

## 🚨 Critical Issues (Immediate Action Required)

### 1. **Terraform State Files in Git Repository**
**Risk Level**: Critical
**Impact**: Security, Data Loss, Conflicts

**Problem**: Terraform state files are committed to git despite .gitignore rules:
```
environments/*/terraform.tfstate
environments/*/terraform.tfstate.backup
```

**Solution**:
```bash
# Immediate cleanup
git rm --cached environments/*/terraform.tfstate*
git commit -m "Remove terraform state files from git"

# Configure remote state backend
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "terraformstate[unique]"
    container_name       = "tfstate"
    key                  = "homelab.terraform.tfstate"
  }
}
```

### 2. **Missing Ceph Storage Infrastructure**
**Risk Level**: Critical
**Impact**: Application Failures, Data Loss

**Problem**: Applications expect `ceph-rbd` storage class but no Ceph cluster exists:
- Terraform configs reference `ceph-rbd` in prod/shared environments
- Only `microk8s-hostpath` storage available
- Missing storage class causing application scheduling failures

**Solution**: Deploy Rook-Ceph or update storage class references:
```bash
# Quick fix: Update terraform.tfvars
sed -i 's/ceph-rbd/microk8s-hostpath/g' environments/*/terraform.tfvars

# Long-term: Deploy Rook-Ceph cluster
kubectl apply -f https://raw.githubusercontent.com/rook/rook/release-1.12/deploy/examples/crds.yaml
```

### 3. **Hardcoded Node References**
**Risk Level**: Critical
**Impact**: Pod Scheduling Failures

**Problem**: Applications reference non-existent nodes:
```yaml
# apps/ollama/base/pv-ollama-model-cache.yaml
nodeAffinity:
  - microk8s-prod-llm1  # Node doesn't exist
```

**Solution**:
```bash
# Update to existing nodes
kubectl get nodes --no-headers | cut -d' ' -f1
# Use: microk8s-prod-node1 instead of microk8s-prod-llm1
```

### 4. **Container Storage Path Mismatch**
**Risk Level**: Critical
**Impact**: Backup Failures

**Problem**: Azure storage containers use different naming in code vs. production:
- Terraform: `commafeed-db`, `linkding-db`, etc.
- Production: `commafeed-db-clean`, `linkding-db-clean`

**Solution**: Align container names in Terraform:
```hcl
locals {
  apps = {
    commafeed = { container_name = "commafeed-db-clean" }
    linkding  = { container_name = "linkding-db-clean" }
    wallabag  = { container_name = "wallabag-db-clean" }
    n8n       = { container_name = "n8n-db-clean" }
    listmonk  = { container_name = "listmonk-db-clean" }
  }
}
```

### 5. **Database Namespace Inconsistency**
**Risk Level**: Critical
**Impact**: Service Discovery, Backup Failures

**Problem**: ArgoCD deploys databases to environment namespaces (dev/qa/prod) but applications expect `cnpg-prod`:
```yaml
# Current: databases deploy to {{path[3]}} namespace (dev/qa/prod)
# Expected: cnpg-prod namespace for production databases
```

**Solution**: Fix namespace consistency in db-applicationset.yaml:
```yaml
destination:
  namespace: 'cnpg-{{path[3]}}'  # cnpg-dev, cnpg-qa, cnpg-prod
```

---

## ⚠️ High Priority Issues

### 6. **Provider Version Constraints Too Loose**
**Risk Level**: High
**Impact**: Unexpected Behavior, Breaking Changes

**Problem**: Version constraints allow major version updates:
```hcl
# Too permissive
azurerm = "~> 3.0"  # Allows 3.999.x
kubernetes = "~> 2.10"  # Allows 2.999.x
```

**Solution**: Use more restrictive constraints:
```hcl
azurerm = "~> 3.116.0"
kubernetes = "~> 2.32.0"
helm = "~> 2.15.0"
```

### 7. **CNPG Operator Version Pinning**
**Risk Level**: High
**Impact**: Database Stability

**Problem**: CNPG operator version is hardcoded to 0.24.0 (outdated):
```hcl
version = "0.24.0"  # Released 6+ months ago
```

**Solution**: Update to latest stable version:
```hcl
version = "0.24.1"  # Or latest from https://cloudnative-pg.github.io/charts
```

### 8. **External Secrets Operator Not Deployed**
**Risk Level**: High
**Impact**: Secret Management Failures

**Problem**: External Secrets module exists but applications can't access Azure Key Vault secrets.

**Solution**: Deploy ESO in shared environment:
```hcl
module "external_secrets" {
  source = "../../modules/external-secrets"
  depends_on = [module.azure_keyvault]
}
```

### 9. **Missing Health Checks and Probes**
**Risk Level**: High
**Impact**: Service Reliability

**Problem**: Applications lack proper health checks:
```yaml
# Missing in most deployments
livenessProbe:
  httpGet:
    path: /health
    port: 8080
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
```

### 10. **Ingress TLS Not Enforced**
**Risk Level**: High
**Impact**: Security

**Problem**: Ingress configs don't enforce HTTPS:
```yaml
# Add to all ingress configs
spec:
  tls:
    - hosts:
        - app.lab.aminrj.com
      secretName: app-tls
  rules:
    - host: app.lab.aminrj.com
      http:
        paths:
        - pathType: Prefix
          path: /
          backend:
            service:
              name: app-service
              port:
                number: 80
```

### 11. **Resource Limits Not Defined**
**Risk Level**: High
**Impact**: Resource Exhaustion, Node Instability

**Problem**: Most applications lack resource limits:
```yaml
# Add to all application deployments
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### 12. **Backup Retention Policy Inconsistency**
**Risk Level**: High
**Impact**: Storage Costs, Compliance

**Problem**: Different retention policies across environments:
- Some apps: 3d retention
- Others: 7d retention
- No clear policy

**Solution**: Standardize retention policy:
```yaml
# databases/*/overlays/*/destination-path-patch.yaml
spec:
  backup:
    retentionPolicy: "7d"  # Standard across all environments
```

### 13. **ArgoCD Application Naming Conflicts**
**Risk Level**: High
**Impact**: GitOps Deployment Failures

**Problem**: Database ApplicationSet creates conflicting names:
```yaml
name: '{{path[1]}}-db-{{path[3]}}'  # May conflict with app names
```

**Solution**: Use unique naming pattern:
```yaml
name: 'db-{{path[1]}}-{{path[3]}}'  # db-linkding-prod vs linkding-prod
```

---

## 📋 Medium Priority Issues

### 14. **Terraform Module Organization**
**Risk Level**: Medium
**Impact**: Maintainability

**Problem**: Modules lack consistent structure and documentation.

**Solution**: Standardize module structure:
```
modules/example/
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── README.md
└── examples/
```

### 15. **Environment Variable Management**
**Risk Level**: Medium
**Impact**: Configuration Drift

**Problem**: Environment-specific configs scattered across multiple files.

**Solution**: Centralize environment configs:
```yaml
# environments/prod/config.yaml
apps:
  n8n:
    replicas: 2
    resources:
      requests: { memory: "1Gi", cpu: "500m" }
      limits: { memory: "4Gi", cpu: "2000m" }
```

### 16. **Missing Monitoring Labels**
**Risk Level**: Medium
**Impact**: Observability

**Problem**: Applications lack consistent monitoring labels:
```yaml
metadata:
  labels:
    app.kubernetes.io/name: linkding
    app.kubernetes.io/version: "1.25.0"
    app.kubernetes.io/component: web
    app.kubernetes.io/part-of: homelab
    app.kubernetes.io/managed-by: argocd
```

### 17. **Security Context Not Enforced**
**Risk Level**: Medium
**Impact**: Security

**Problem**: Containers run as root by default.

**Solution**: Add security contexts:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

### 18. **Network Policies Missing**
**Risk Level**: Medium
**Impact**: Security, Network Segmentation

**Solution**: Implement namespace-level network policies:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 19. **Kustomize Base Duplication**
**Risk Level**: Medium
**Impact**: Maintainability

**Problem**: Similar configurations duplicated across application bases.

**Solution**: Create shared base components:
```
infrastructure/shared-bases/
├── web-app/          # Common web app patterns
├── database/         # Common database patterns
└── monitoring/       # Common monitoring configs
```

### 20. **Git Repository URL Hardcoding**
**Risk Level**: Medium
**Impact**: Portability

**Problem**: ArgoCD ApplicationSets hardcode specific Git repository URL.

**Solution**: Use environment variables or Helm values:
```yaml
repoURL: '{{ .Values.git.repoUrl | default "https://github.com/aminrj/homelab-terraform-gitops-infra.git" }}'
```

---

## 💡 Low Priority Improvements

### 21. **Terraform State Locking**
**Risk Level**: Low
**Impact**: Concurrent Modification Protection

**Solution**: Add DynamoDB table for state locking:
```hcl
terraform {
  backend "azurerm" {
    # ... existing config
    use_azuread_auth = true
  }
}
```

### 22. **Documentation Automation**
**Risk Level**: Low
**Impact**: Documentation Drift

**Solution**: Add terraform-docs automation:
```yaml
# .github/workflows/docs.yml
- name: Generate terraform docs
  uses: terraform-docs/gh-actions@main
```

### 23. **Dependency Automation**
**Risk Level**: Low
**Impact**: Security, Maintenance

**Solution**: Add Dependabot configuration:
```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "terraform"
    directory: "/"
    schedule:
      interval: "weekly"
```

---

## Implementation Priority Matrix

| Priority | Issues | Estimated Effort | Business Impact |
|----------|--------|------------------|-----------------|
| Critical | 5 | 2-3 days | High - System stability |
| High | 8 | 3-5 days | Medium - Security & reliability |
| Medium | 7 | 5-7 days | Low - Long-term maintainability |
| Low | 3 | 2-3 days | Low - Quality of life |

## Quick Wins (< 2 hours each)

1. Fix hardcoded node references in ollama config
2. Update storage class from ceph-rbd to microk8s-hostpath
3. Remove terraform state files from git
4. Pin provider versions to specific minor versions
5. Add resource limits to high-memory applications (n8n, wallabag)

## Recommended Implementation Order

**Week 1 (Critical)**:
1. Remove terraform state files from git + setup remote backend
2. Fix storage class references
3. Fix hardcoded node names
4. Align storage container naming
5. Fix database namespace consistency

**Week 2 (High Priority)**:
1. Update provider versions
2. Deploy External Secrets Operator
3. Add resource limits to all applications
4. Implement health checks
5. Enforce HTTPS on all ingresses

**Week 3-4 (Medium Priority)**:
1. Standardize Terraform modules
2. Add monitoring labels
3. Implement security contexts
4. Create network policies
5. Reduce configuration duplication

**Ongoing (Low Priority)**:
1. Automate documentation
2. Setup dependency updates
3. Improve CI/CD pipeline

---

## Validation Checklist

After implementing fixes, verify:

- [ ] All applications can be scheduled and start successfully
- [ ] Database backups complete without errors
- [ ] External secrets are properly synchronized
- [ ] All ingresses serve content over HTTPS
- [ ] Resource usage stays within defined limits
- [ ] ArgoCD can sync all applications without conflicts
- [ ] Terraform plan shows no unexpected changes

---

**Next Steps**: Begin with critical fixes, focusing on storage and state management issues that are currently preventing proper application deployment.