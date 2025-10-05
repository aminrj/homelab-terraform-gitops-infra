# ArgoCD ApplicationSets: Auto-Discovering Apps Without Repetitive YAML

*How to manage dozens of applications across multiple environments with a single 31-line ApplicationSet, using directory-based auto-discovery patterns.*

## The Problem with Traditional ArgoCD Applications

When I started with ArgoCD, I manually created an Application for each app in each environment:

```yaml
# One file for each app/environment combination
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/aminrj/homelab-terraform-gitops-infra.git
    targetRevision: main
    path: apps/n8n/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: n8n-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n-qa
  # ... repeat for QA
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: commafeed-prod
  # ... repeat for commafeed
# ... etc for 15+ applications
```

This is tedious, error-prone, and doesn't scale. Enter ApplicationSets.

## The ApplicationSet Solution

One ApplicationSet can create dozens of ArgoCD Applications automatically by discovering them from your Git repository structure:

```yaml
# argocd/applicationset.yaml - This replaces 15+ individual Application files
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/aminrj/homelab-terraform-gitops-infra.git
        revision: main
        directories:
          - path: apps/*/overlays/*
  template:
    metadata:
      name: '{{path[1]}}-{{path[3]}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/aminrj/homelab-terraform-gitops-infra.git
        targetRevision: main
        path: 'apps/{{path[1]}}/overlays/{{path[3]}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path[1]}}-{{path[3]}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

**What this does:**
- Scans your Git repo for directories matching `apps/*/overlays/*`
- For each match, creates an ArgoCD Application
- Names applications using `{app-name}-{environment}` pattern
- Automatically deploys to appropriate namespaces

## How Directory Discovery Works

Given this Git repository structure:

```
apps/
├── n8n/
│   └── overlays/
│       ├── dev/
│       ├── qa/
│       └── prod/
├── commafeed/
│   └── overlays/
│       ├── qa/
│       └── prod/
└── linkding/
    └── overlays/
        └── prod/
```

The ApplicationSet generates:

```bash
$ kubectl get applications -n argocd
NAME              SYNC STATUS   HEALTH
n8n-dev           Synced        Healthy
n8n-qa            Synced        Healthy
n8n-prod          Synced        Healthy
commafeed-qa      Synced        Healthy
commafeed-prod    Synced        Healthy
linkding-prod     Synced        Healthy
```

**Path template explained:**

```yaml
path: apps/*/overlays/*
#          ^1    ^3

# path[0] = "apps"
# path[1] = app name (n8n, commafeed, etc.)
# path[2] = "overlays"
# path[3] = environment (dev, qa, prod)

name: '{{path[1]}}-{{path[3]}}'  # Results in: n8n-prod, commafeed-qa, etc.
```

## Adding a New Application

With ApplicationSets, adding a new application is trivial:

```bash
# Create directory structure
mkdir -p apps/wallabag/overlays/prod

# Add kustomization
cat > apps/wallabag/overlays/prod/kustomization.yaml <<EOF
resources:
  - ../../base
namespace: wallabag-prod
EOF

# Commit and push
git add apps/wallabag
git commit -m "Add wallabag application"
git push

# ArgoCD automatically creates wallabag-prod application
# No manual Application creation needed!
```

Within minutes:

```bash
$ kubectl get applications -n argocd | grep wallabag
wallabag-prod     OutOfSync    Missing
# ArgoCD detected the new directory and created the application

# After sync:
wallabag-prod     Synced       Healthy
```

## Multiple ApplicationSets for Different Resource Types

I use separate ApplicationSets for apps vs. databases:

```yaml
# argocd/applicationset-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: apps
spec:
  generators:
    - git:
        directories:
          - path: apps/*/overlays/*
  template:
    metadata:
      name: '{{path[1]}}-{{path[3]}}'
    spec:
      source:
        path: 'apps/{{path[1]}}/overlays/{{path[3]}}'
      destination:
        namespace: '{{path[1]}}-{{path[3]}}'
---
# argocd/applicationset-databases.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: databases
spec:
  generators:
    - git:
        directories:
          - path: databases/*/overlays/*
  template:
    metadata:
      name: 'db-{{path[1]}}-{{path[3]}}'  # Prefix with "db-"
    spec:
      source:
        path: 'databases/{{path[1]}}/overlays/{{path[3]}}'
      destination:
        namespace: 'cnpg-{{path[3]}}'  # All databases in cnpg-{env}
```

This creates:

```bash
$ kubectl get applications -n argocd
# Applications
n8n-prod            apps/n8n/overlays/prod          n8n-prod
commafeed-prod      apps/commafeed/overlays/prod    commafeed-prod

# Databases
db-n8n-prod         databases/n8n/overlays/prod     cnpg-prod
db-commafeed-prod   databases/commafeed/overlays/prod   cnpg-prod
```

## Advanced Patterns

### Pattern 1: Filter by Path

Only deploy specific apps:

```yaml
generators:
  - git:
      directories:
        - path: apps/prod-only/*/overlays/prod  # Only prod deployments
```

### Pattern 2: Add Labels

Label applications for easier filtering:

```yaml
template:
  metadata:
    name: '{{path[1]}}-{{path[3]}}'
    labels:
      app-name: '{{path[1]}}'
      environment: '{{path[3]}}'
      managed-by: applicationset
```

```bash
# Find all prod applications
kubectl get applications -n argocd -l environment=prod

# Find all n8n applications across environments
kubectl get applications -n argocd -l app-name=n8n
```

### Pattern 3: Different Sync Policies per Environment

```yaml
template:
  metadata:
    name: '{{path[1]}}-{{path[3]}}'
  spec:
    syncPolicy:
      automated:
        prune: '{{path[3] != "prod"}}'  # Auto-prune only non-prod
        selfHeal: true
```

### Pattern 4: Infrastructure ApplicationSet

```yaml
# argocd/applicationset-infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure
spec:
  generators:
    - git:
        directories:
          - path: infrastructure/*/overlays/*
  template:
    metadata:
      name: 'infra-{{path[1]}}-{{path[3]}}'
    spec:
      source:
        path: 'infrastructure/{{path[1]}}/overlays/{{path[3]}}'
      destination:
        namespace: '{{path[1]}}'  # Use component name as namespace
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true  # For CRDs
```

Example infrastructure structure:

```
infrastructure/
├── external-secrets/
│   └── overlays/
│       └── prod/
├── cert-manager/
│   └── overlays/
│       └── prod/
└── monitoring/
    └── overlays/
        ├── dev/
        └── prod/
```

Creates:

```
infra-external-secrets-prod
infra-cert-manager-prod
infra-monitoring-dev
infra-monitoring-prod
```

## Managing ApplicationSet Lifecycle

### Initial Deployment

```bash
# Deploy ApplicationSet
kubectl apply -f argocd/applicationset.yaml

# Watch applications being created
kubectl get applications -n argocd -w

# All discovered apps will be created automatically
```

### Disabling Auto-Discovery Temporarily

```yaml
spec:
  generators:
    - git:
        directories:
          - path: apps/*/overlays/*
            exclude: apps/disabled-app/*  # Exclude specific app
```

Or use Git to control:

```bash
# Temporarily remove from Git to stop auto-discovery
git mv apps/n8n apps/.archived/n8n
git commit -m "Temporarily disable n8n"
git push

# ArgoCD will delete n8n-* applications (if prune: true)
```

### Updating All Applications

```bash
# Change base configuration
vim apps/base/common-labels.yaml

git commit -am "Update common labels"
git push

# All applications sync automatically
# Thanks to selfHeal: true
```

## Troubleshooting

### Problem: Applications Not Auto-Created

**Check generator matches:**

```bash
# See what the generator discovers
kubectl get applicationset apps -n argocd -o yaml

# Look for status section:
# status:
#   conditions:
#   - type: ResourcesUpToDate
#     status: "True"
```

**Test path pattern locally:**

```bash
cd ~/homelab-terraform-gitops-infra

# Simulate ApplicationSet discovery
find apps -type d -path "apps/*/overlays/*"

# Should output:
# apps/n8n/overlays/prod
# apps/n8n/overlays/qa
# ...
```

### Problem: Wrong Namespace

ApplicationSets use template variables. Verify:

```yaml
destination:
  namespace: '{{path[1]}}-{{path[3]}}'
  # For apps/n8n/overlays/prod:
  # path[1] = n8n
  # path[3] = prod
  # Result: n8n-prod
```

### Problem: Applications Deleted Unexpectedly

If you delete directories from Git, ApplicationSets delete corresponding Applications:

```bash
# Don't do this unless you mean it:
git rm -rf apps/n8n/overlays/qa
git commit -m "Remove QA"
git push

# This deletes the n8n-qa Application and all its resources!
```

**Prevention:**

```yaml
syncPolicy:
  automated:
    prune: false  # Don't auto-delete
```

Or use `preserve` annotation:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
```

## Best Practices

1. **Use Consistent Directory Structure**
   ```
   apps/
     {app-name}/
       base/
       overlays/
         {environment}/
   ```

2. **Separate Concerns**
   - `apps/` - Application deployments
   - `databases/` - Database clusters
   - `infrastructure/` - Cluster infrastructure

3. **Name Things Predictably**
   - ApplicationSet name: `apps`, `databases`, `infrastructure`
   - App names: `{component}-{environment}`
   - Namespaces: Match application names

4. **Test Before Deploying**
   ```bash
   # Dry-run with kubectl
   kubectl apply -f argocd/applicationset.yaml --dry-run=client

   # Check what would be created
   # Look at generated template
   ```

5. **Monitor ApplicationSet Health**
   ```bash
   kubectl get applicationsets -n argocd
   kubectl describe applicationset apps -n argocd
   ```

## Conclusion

ApplicationSets eliminate repetitive YAML and enable GitOps at scale:

**Before:**
- 15+ hand-written Application files
- Manual updates for each app/environment
- Error-prone copy-paste

**After:**
- 1 ApplicationSet (31 lines)
- Auto-discovery from Git structure
- Add app = create directory

**Benefits:**
- DRY principle
- Self-service app onboarding
- Consistent patterns enforced
- Scales to hundreds of apps

Your Git repository structure becomes your application catalog.

---

**Related Reading:**
- [Kustomize Overlays in Practice](#) - Directory structure patterns
- [Terraform + ArgoCD GitOps Stack](#) - Complete infrastructure setup
- [GitOps Disaster Recovery](#) - How ArgoCD enables quick recovery

**Code Repository:** [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
