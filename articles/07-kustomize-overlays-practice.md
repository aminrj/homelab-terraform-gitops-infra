# Kustomize Overlays in Practice: Managing 5 Apps Across 3 Environments with Minimal Duplication

*Real-world Kustomize patterns from managing n8n, commafeed, linkding, listmonk, and wallabag across dev, QA, and production environments.*

## The Challenge

I manage 5 applications across 3 environments. Without Kustomize, that's 15 sets of nearly-identical YAML files. With Kustomize overlays, I maintain one base configuration and small environment-specific patches.

**Directory Structure:**

```
apps/n8n/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── ingress.yaml
    │   └── secrets.yaml
    ├── qa/
    │   └── ... (similar)
    └── prod/
        └── ... (similar)
```

## Base Configuration: The Foundation

Base contains the common configuration shared across all environments:

```yaml
# apps/n8n/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app: n8n
  managed-by: kustomize
```

```yaml
# apps/n8n/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
spec:
  replicas: 1  # Overridden in overlays
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      containers:
      - name: n8n
        image: n8nio/n8n:latest
        ports:
        - containerPort: 5678
        env:
        - name: DB_POSTGRESDB_HOST
          value: placeholder  # Replaced in overlays
        - name: N8N_ENCRYPTION_KEY
          valueFrom:
            secretKeyRef:
              name: n8n-encryption
              key: key
        resources:
          requests:
            memory: "256Mi"  # Overridden in overlays
            cpu: "100m"
```

## Production Overlay: Patching for Scale

```yaml
# apps/n8n/overlays/prod/kustomization.yaml
namePrefix: ""
nameSuffix: ""
namespace: n8n-prod

resources:
  - ../../base
  - namespace.yaml
  - ingress.yaml
  - secrets.yaml

patches:
  - target:
      kind: Deployment
      name: n8n
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 2
      
      - op: replace
        path: /spec/template/spec/containers/0/resources
        value:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: n8n-db-cnpg-v3-rw.cnpg-prod.svc.cluster.local
```

**What this does:**
- Increases replicas from 1 to 2 (HA)
- Doubles resource limits
- Points to production database

## QA Overlay: Testing Configuration

```yaml
# apps/n8n/overlays/qa/kustomization.yaml
namespace: n8n-qa

resources:
  - ../../base
  - namespace.yaml
  - ingress.yaml
  - secrets.yaml

patches:
  - target:
      kind: Deployment
      name: n8n
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: n8n-db-cnpg-v3-rw.cnpg-qa.svc.cluster.local
      
      # Reduce resources for QA
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "256Mi"
      
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "512Mi"
```

## Testing Overlays Locally

```bash
# Preview what will be applied
kubectl kustomize apps/n8n/overlays/prod

# Compare environments
diff <(kubectl kustomize apps/n8n/overlays/prod) \
     <(kubectl kustomize apps/n8n/overlays/qa)

# Apply to cluster
kubectl apply -k apps/n8n/overlays/prod
```

## Advanced Pattern: Strategic Merge vs. JSON Patch

### Strategic Merge (Simpler)

```yaml
# apps/commafeed/overlays/prod/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: commafeed
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: commafeed
        resources:
          limits:
            memory: 1Gi
```

```yaml
# kustomization.yaml
patchesStrategicMerge:
  - deployment-patch.yaml
```

### JSON Patch (More Control)

```yaml
# kustomization.yaml
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/env/-
        value:
          name: NEW_VAR
          value: "new value"
```

## Real-World Patterns

### Pattern 1: Database Host Per Environment

```yaml
# base/deployment.yaml
env:
  - name: DB_HOST
    value: REPLACE_ME  # Placeholder

# overlays/prod/kustomization.yaml
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: app-db-cnpg-v1-rw.cnpg-prod.svc.cluster.local

# overlays/qa/kustomization.yaml
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: app-db-cnpg-v1-rw.cnpg-qa.svc.cluster.local
```

### Pattern 2: Ingress Per Environment

```yaml
# overlays/prod/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n-ingress-prod
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  rules:
  - host: n8n.example.com  # Production domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: n8n
            port:
              number: 5678
  tls:
  - hosts:
    - n8n.example.com
    secretName: n8n-tls-prod

# overlays/qa/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n-ingress-qa
spec:
  rules:
  - host: n8n-qa.example.com  # QA subdomain
    # ... rest similar
```

### Pattern 3: Secrets Per Environment

```yaml
# overlays/prod/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-db-creds
spec:
  secretStoreRef:
    name: azure-keyvault-prod  # Prod Key Vault
  data:
    - secretKey: password
      remoteRef:
        key: n8n-db-password-prod

# overlays/qa/secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: n8n-db-creds
spec:
  secretStoreRef:
    name: azure-keyvault-qa  # QA Key Vault
  data:
    - secretKey: password
      remoteRef:
        key: n8n-db-password-qa
```

## Common Pitfalls

### Pitfall 1: Array Index Changes

```yaml
# BAD - Fragile if array order changes
- op: replace
  path: /spec/template/spec/containers/0/env/2/value
  value: newvalue

# GOOD - Use name matching
patches:
- target:
    kind: Deployment
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/env/-
      value:
        name: SPECIFIC_VAR
        value: newvalue
```

### Pitfall 2: Forgetting Namespace

```yaml
# Resources created in wrong namespace
kubectl apply -k apps/n8n/overlays/prod

# Fix: Always set namespace in kustomization
namespace: n8n-prod
```

## Complete Real Example: Linkding

Base:

```yaml
# apps/linkding/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: linkding
spec:
  replicas: 1
  selector:
    matchLabels:
      app: linkding
  template:
    metadata:
      labels:
        app: linkding
    spec:
      containers:
      - name: linkding
        image: sissbruecker/linkding:latest
        ports:
        - containerPort: 9090
        env:
        - name: LD_DB_HOST
          value: REPLACE
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
```

Prod Overlay:

```yaml
# apps/linkding/overlays/prod/kustomization.yaml
namespace: linkding

resources:
  - ../../base
  - ingress.yaml
  - secrets.yaml

patches:
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: linkding-db-cnpg-v1-rw.cnpg-prod.svc.cluster.local
```

Deploy:

```bash
kubectl apply -k apps/linkding/overlays/prod/
```

## Conclusion

Kustomize overlays enable DRY Kubernetes configurations:

**Benefits:**
- Single source of truth (base)
- Environment-specific patches
- No template engine complexity
- Native kubectl support

**My setup:**
- 5 apps × 3 environments = 15 deployments
- Managed with ~20 base files
- ~45 small overlay files
- 0 duplicated configuration

Kustomize makes multi-environment GitOps practical.

---

**Related Reading:**
- [ArgoCD ApplicationSets](#) - Auto-discovering Kustomize overlays
- [CNPG Multi-Environment Strategy](#) - Database overlay patterns
- [Terraform + ArgoCD GitOps Stack](#) - Complete infrastructure

**Code Repository:** [github.com/aminrj/homelab-terraform-gitops-infra](https://github.com/aminrj/homelab-terraform-gitops-infra)
