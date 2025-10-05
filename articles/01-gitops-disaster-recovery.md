# GitOps Disaster Recovery: How I Accidentally Deleted Production (And Recovered in 5 Minutes)

*TL;DR: I accidentally deleted all my production applications with a grep command. GitOps saved me. Here's what happened and what I learned about building resilient infrastructure.*

## The Incident

It was a routine cleanup operation. I wanted to free up cluster resources by deleting all QA namespaces while keeping the configurations in Git for future use. Simple enough, right?

I had identified all the QA ArgoCD applications and crafted what I thought was a surgical command:

```bash
kubectl get applications -n argocd | grep -i qa | awk '{print $1}' | xargs kubectl delete application -n argocd
```

The command executed successfully. Too successfully.

Within seconds, my production applications started disappearing. Commafeed - gone. N8n - gone. My heart sank as I realized what had happened.

## What Went Wrong

The problem wasn't with the individual commands - it was with how they worked together. Let me break down what actually happened:

```bash
# What I thought would happen:
# 1. Get all applications
# 2. Filter for QA applications (commafeed-qa, n8n-qa, etc.)
# 3. Delete only those

# What actually happened:
kubectl get applications -n argocd
# Returns ALL applications, including:
# - commafeed-qa
# - commafeed-prod
# - n8n-qa
# - n8n-prod
# - db-commafeed-prod
# - etc.

# Then grep -i qa matched more than I expected
# The -i flag makes it case-insensitive
# But more importantly, it was matching ANY line containing 'qa'
```

The real issue? I hadn't properly tested my grep pattern. Here's what I should have used:

```bash
# WRONG (what I used):
grep -i qa  # Matches any line with 'qa' anywhere

# RIGHT (what I should have used):
grep -- '-qa$'  # Matches only lines ending with '-qa'
# Or even better:
grep -E -- '-(qa)\s'  # Matches '-qa' followed by whitespace
```

## The Recovery

Here's where GitOps architecture proved its worth. Because all my application configurations were stored in Git using Kustomize overlays, recovery was straightforward:

```bash
# Check what's running (or not running)
kubectl get pods --all-namespaces | grep -E "n8n|commafeed"
# Output: Nothing. Namespaces were empty.

# Check if databases survived
kubectl get clusters -n cnpg-prod
# Output: All healthy! Databases were separate ArgoCD applications.

# Restore applications from Git
kubectl apply -k apps/n8n/overlays/prod/
kubectl apply -k apps/commafeed/overlays/prod/
kubectl apply -k apps/linkding/overlays/prod/
kubectl apply -k apps/listmonk/overlays/prod/
kubectl apply -k apps/wallabag/overlays/prod/
```

Within 5 minutes, everything was back online. My n8n workflows, user data, bookmarks - all intact.

## Why GitOps Saved Me

Let's talk about the architecture decisions that made this recovery possible:

### 1. **Infrastructure as Code**

Every application deployment is defined in Git:

```yaml
# apps/n8n/overlays/prod/kustomization.yaml
resources:
  - ../../base
  - secrets.yaml
  - ingress.yaml
  - namespace.yaml

namespace: n8n-prod

patches:
  - target:
      kind: Deployment
      name: n8n
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: n8n-db-cnpg-v3-rw.cnpg-prod.svc.cluster.local
```

This means the **entire application configuration** lives in version control. No clickops, no imperative `kubectl create` commands that leave you guessing what was deployed.

### 2. **Separation of Concerns: Apps vs. Databases**

My ArgoCD ApplicationSet creates separate applications for databases and apps:

```yaml
# Two separate ApplicationSets:
# 1. apps/*/overlays/* → Creates application deployments
# 2. databases/*/overlays/* → Creates database clusters

# This means deleting app ArgoCD applications doesn't touch databases
```

When I deleted the application definitions, the database clusters (and their data) remained completely untouched:

```bash
$ kubectl get clusters -n cnpg-prod
NAME                   AGE    INSTANCES   READY   STATUS
n8n-db-cnpg-v3         1h     2           2       Cluster in healthy state
commafeed-db-cnpg-v1   3h     1           1       Cluster in healthy state
linkding-db-cnpg-v1    15d    1           1       Cluster in healthy state
```

### 3. **Declarative State in Git**

The recovery command `kubectl apply -k apps/n8n/overlays/prod/` worked because it reads the entire desired state from Git and applies it:

```bash
# What gets created:
namespace/n8n-prod created
configmap/n8n-custom-node created
configmap/n8n-db-config created
service/n8n created
persistentvolumeclaim/n8n-data created
deployment.apps/n8n created
externalsecret.external-secrets.io/n8n-db-creds created
externalsecret.external-secrets.io/n8n-encryption created
ingress.networking.k8s.io/n8n-ingress-prod created
```

All from a single directory structure in Git. No manual steps, no "oh I forgot to configure X" moments.

## The Lessons

### 1. **Test Destructive Commands First**

Before running any destructive operation, test the selection logic:

```bash
# ALWAYS test the query first
kubectl get applications -n argocd | grep -E -- '-(qa)\s'
# Review the output carefully
# Count how many lines you expect vs. what you see

# Only then add the delete
kubectl get applications -n argocd | grep -E -- '-(qa)\s' | awk '{print $1}' | xargs -t kubectl delete application -n argocd
#                                                                                 ^^
# The -t flag shows each command before execution - one last sanity check
```

Better yet, save the list to a file first:

```bash
# Save to file for review
kubectl get applications -n argocd | grep -E -- '-(qa)\s' > /tmp/apps-to-delete.txt

# Review carefully
cat /tmp/apps-to-delete.txt

# Then delete
cat /tmp/apps-to-delete.txt | awk '{print $1}' | xargs kubectl delete application -n argocd
```

### 2. **Separate Application State from Data State**

My architecture naturally separates these concerns:

```
apps/
  n8n/
    base/               # Application deployment config
    overlays/
      prod/             # Production-specific config

databases/
  n8n/
    base/               # Database cluster config
    overlays/
      prod/             # Production database config
```

This means I can safely delete and recreate applications without touching data. The application connects to the database via service discovery:

```yaml
# In the app deployment:
env:
  - name: DB_POSTGRESDB_HOST
    value: n8n-db-cnpg-v3-rw.cnpg-prod.svc.cluster.local
    #      ^cluster-name ^namespace    ^service-type
```

As long as the database cluster exists and the naming is consistent, apps reconnect automatically.

### 3. **Design for Operator Error**

Humans make mistakes. Your infrastructure should be resilient to those mistakes:

**✅ Good:**
- All configuration in Git (can restore from source of truth)
- Separate ArgoCD apps for data vs. compute
- Immutable infrastructure (recreate rather than modify)
- Clear naming conventions (`app-env` pattern)

**❌ Bad:**
- Imperative configuration (can't easily restore)
- Monolithic deployments (one mistake affects everything)
- Shared resources across environments
- Cryptic resource names

### 4. **Use ArgoCD's Safety Features**

ArgoCD has protection mechanisms I wasn't fully utilizing:

```yaml
# argocd/applicationset.yaml
syncPolicy:
  automated:
    prune: true        # Auto-delete resources not in Git
    selfHeal: true     # Auto-correct drift
  syncOptions:
    - CreateNamespace=true

# Add these for protection:
syncPolicy:
  syncOptions:
    - PruneLast=true   # Delete resources last, after creating new ones
    - RespectIgnoreDifferences=true
  automated:
    prune: true
    selfHeal: true
    allowEmpty: false  # Prevent deletion if Git is empty
```

## The Recovery Playbook

If this happens to you, here's the step-by-step recovery process:

### Step 1: Don't Panic, Assess Damage

```bash
# What's missing?
kubectl get deployments --all-namespaces
kubectl get applications -n argocd

# What's still healthy?
kubectl get clusters --all-namespaces  # Check databases
kubectl get pods -n cnpg-prod           # Check database pods
```

### Step 2: Verify Data Integrity

```bash
# For each critical database:
kubectl cnpg status n8n-db-cnpg-v3 -n cnpg-prod

# Expected output:
# Cluster in healthy state
# Primary: n8n-db-cnpg-v3-1
# Instances: 2/2 ready
```

### Step 3: Restore Applications from Git

```bash
# For each application that's missing:
kubectl apply -k apps/n8n/overlays/prod/
kubectl apply -k apps/commafeed/overlays/prod/
# etc.

# Wait for pods to be ready:
kubectl wait --for=condition=ready pod -l app=n8n -n n8n-prod --timeout=300s
```

### Step 4: Verify Application Connectivity

```bash
# Check if apps can connect to databases:
kubectl logs -n n8n-prod deployment/n8n --tail=50 | grep -i "database\|postgres\|connection"

# Should see successful connection messages
# If you see connection errors, check:
# 1. Database service names
# 2. External secrets synchronization
# 3. Network policies
```

### Step 5: Test Critical Functions

Don't just trust that pods are running - actually test:

```bash
# Port-forward to test locally:
kubectl port-forward -n n8n-prod svc/n8n 5678:5678

# Open browser to http://localhost:5678
# Log in and verify:
# - User data is intact
# - Workflows are present
# - Executions are accessible
```

## Building a More Resilient Setup

After this incident, I've made several improvements:

### 1. **Add Deletion Protection to Critical Resources**

```yaml
# For production databases:
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: n8n-db-cnpg-v3
  annotations:
    argocd.argoproj.io/sync-options: Delete=false
    #  ^ Prevents ArgoCD from deleting this resource
```

### 2. **Implement a Safer Cleanup Script**

```bash
#!/bin/bash
# cleanup-qa.sh - Safely remove QA environments

set -euo pipefail

ENV="qa"

echo "==> This will delete all ${ENV} resources"
echo "==> Listing resources to be deleted:"
echo ""

# Show exactly what will be deleted
kubectl get applications -n argocd | grep -E -- "-${ENV}\s" | tee /tmp/apps-to-delete.txt
kubectl get namespaces | grep -E "${ENV}" | tee -a /tmp/apps-to-delete.txt

echo ""
read -p "Delete these resources? (type 'yes' to confirm): " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Delete ArgoCD applications first
kubectl get applications -n argocd -o name | grep -- "-${ENV}" | xargs kubectl delete -n argocd

# Wait for resources to be cleaned up by ArgoCD
echo "Waiting for ArgoCD to clean up resources..."
sleep 30

# Force delete any stuck namespaces
for ns in $(kubectl get namespaces -o name | grep "${ENV}"); do
    kubectl delete "$ns" --force --grace-period=0 || true
done

echo "==> Cleanup complete"
```

### 3. **Environment-Specific Annotations**

```yaml
# Add to prod resources for extra safety:
metadata:
  annotations:
    environment: production
    protect: "true"

# Then query with:
kubectl get applications -n argocd -o json | \
  jq -r '.items[] | select(.metadata.annotations.environment=="production") | .metadata.name'
```

## Monitoring and Alerts

Post-incident, I added monitoring for unexpected deletions:

```yaml
# Example Prometheus alert:
- alert: ProductionApplicationDeleted
  expr: |
    count(kube_deployment_labels{namespace=~".*-prod"})
    <
    count(kube_deployment_labels{namespace=~".*-prod"} offset 5m)
  for: 1m
  annotations:
    summary: "Production deployment count decreased"
    description: "{{ $value }} production deployments were deleted"
```

## Conclusion

Deleting production was terrifying, but it validated my architecture choices:

1. **GitOps works**: Recovery was a simple `kubectl apply -k`
2. **Separation of concerns works**: Databases survived because they were separate resources
3. **Declarative configuration works**: No guessing what was configured, it's all in Git

The incident took 30 seconds. The recovery took 5 minutes. The lessons will last a lifetime.

**Key Takeaways:**
- Test destructive commands before executing
- Keep data separate from compute
- Version control everything
- Design for human error
- Practice your recovery procedures

Your infrastructure will fail. Design it to be recoverable.

---

**Related Reading:**
- [CNPG Backup and Restore Patterns](#) - How I back up databases to Azure
- [ArgoCD ApplicationSets](#) - Auto-discovering apps from Git structure
- [Terraform + ArgoCD: The Complete GitOps Stack](#) - How I set up this infrastructure

**Code Repository:** All configurations shown are available at [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
