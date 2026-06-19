# HolmesGPT AI-SRE Agent — Full Guide (and whole-repo reference)

This document explains how the cluster is put together and, in depth, how the new
**AI-lab** track (an observable, read-only HolmesGPT SRE agent) is deployed,
configured, tested, and operated. It is written to be valid for the whole repo:
Part 1 is a reference map of the cluster; Parts 2–8 cover the AI-lab additions.

> **Golden rule of this repo:** nothing is applied by hand to the cluster. Terraform
> provisions infrastructure; ArgoCD syncs everything else from `main`. You change the
> system by committing to Git (and, for the infra layer, running `terraform apply`).

---

## Table of contents

1. [Cluster reference map](#1-cluster-reference-map)
2. [What the AI-lab adds and why](#2-what-the-ai-lab-adds-and-why)
3. [Architecture & data flow](#3-architecture--data-flow)
4. [The security model](#4-the-security-model)
5. [File map of the AI-lab track](#5-file-map-of-the-ai-lab-track)
6. [Configuration reference (every TODO)](#6-configuration-reference-every-todo)
7. [Bootstrap & deploy order](#7-bootstrap--deploy-order)
8. [Testing & verification](#8-testing--verification)
9. [Troubleshooting](#9-troubleshooting)
10. [Day-2 operations](#10-day-2-operations)

---

## 1. Cluster reference map

**Platform:** single MicroK8s cluster (Proxmox VMs), GitOps-managed.
**Control split:** Terraform = foundational infra (manual `apply`); ArgoCD = apps,
databases, infrastructure overlays (auto-sync from `main`, prune + selfHeal).

### Repo layout

| Path | Purpose | Applied by |
|---|---|---|
| `environments/{shared,prod,qa,dev}/` | Terraform roots (`shared` = core infra) | Terraform |
| `modules/` | Reusable Terraform modules | Terraform |
| `argocd/` | AppProjects / ApplicationSets (bootstrapped via the `argocd-infrastructure` module) | Terraform → ArgoCD |
| `apps/<app>/{base,overlays/prod}` | App Kustomize manifests | ArgoCD |
| `databases/<app>/{base,overlays/prod}` | CloudNativePG `Cluster` CRs + backups | ArgoCD |
| `infrastructure/<comp>/overlays/prod` | Monitoring, dashboards, network policies, **tempo** | ArgoCD |
| `ai-lab/<comp>/{base,overlays/prod}` | **New:** HolmesGPT agent + MCP servers + collector | ArgoCD |
| `docs/` | Architecture, operations runbooks, this guide | — |

### Core infrastructure namespaces

| Component | Namespace | Notes |
|---|---|---|
| ArgoCD | `argocd` | GitOps controller |
| CloudNativePG operator | `cnpg-system` | DB clusters live in `cnpg-prod` |
| External Secrets Operator | `external-secrets` | `ClusterSecretStore: azure-kv-store-prod` |
| cert-manager | `cert-manager` | issuer `letsencrypt-prod` |
| MetalLB | `metallb-system` | pool `10.0.30.200-10.0.30.220` |
| Prometheus + Grafana | `monitoring` | `kube-prometheus-stack-grafana` (LB `10.0.30.203`) |
| **Tempo (new)** | `monitoring` | traces backend for agent telemetry |
| **AI-lab agent (new)** | `ai-lab` | isolated trust zone |

### Applications

Ingress domain: `*.lab.aminrj.com` (TLS via `letsencrypt-prod`). Databases are
CloudNativePG clusters in `cnpg-prod`, backed up to Azure Blob (Barman, 7-day
retention, continuous WAL).

| App | Namespace | DB cluster (`cnpg-prod`) |
|---|---|---|
| linkding | `linkding` | linkding-db-cnpg-v1 |
| commafeed | `commafeed-prod` | commafeed-db-cnpg-v1 |
| n8n | `n8n-prod` | n8n-db-cnpg-v1 |
| listmonk | `listmonk-prod` | listmonk-db-cnpg-v1 |
| gitea | `gitea-prod` | gitea-db-cnpg-v1 |
| threat-intell | `threat-intel` | threat-intel-db-cnpg-v1 |
| wallabag | `wallabag-prod` | (unused / excluded) |

### How secrets work (existing pattern)

Terraform writes secrets into **Azure Key Vault** → **External Secrets Operator**
syncs them into K8s `Secret`s via `ExternalSecret` CRs that reference a
`ClusterSecretStore` (`azure-kv-store-prod`, ServicePrincipal auth, secret
`azure-creds-prod` in `external-secrets`). No app/DB secrets live in Git.

The AI-lab deliberately does **not** use that cluster-wide store — see §4.

---

## 2. What the AI-lab adds and why

A read-only AI SRE agent (**HolmesGPT**) that can investigate the cluster and
explain incidents, with three load-bearing properties:

1. **Read-only by default** — enforced at each MCP server *and* the upstream token,
   not by trusting the LLM.
2. **Isolated trust zone** — its own namespace, ArgoCD `AppProject`, a *separate*
   Key Vault scope via a **namespaced** `SecretStore`, and a default-deny network.
3. **Fully observed** — every LLM call and tool invocation is emitted as
   OpenTelemetry GenAI traces/metrics into the same Prometheus/Grafana/Tempo stack
   the agent investigates.

Components:

| Component | Image / chart | Role |
|---|---|---|
| HolmesGPT | `robusta/holmes` Helm chart | The agent runtime (uses LiteLLM internally) |
| Grafana MCP | `mcp/grafana` | Read-only metrics/logs/dashboards |
| Argo CD MCP | `ghcr.io/argoproj-labs/argocd-mcp` | Read-only GitOps app state |
| OTel Collector | `otel/opentelemetry-collector-contrib` | Receives agent telemetry |
| Tempo | `grafana/tempo` | Trace storage (in `monitoring`) |

---

## 3. Architecture & data flow

```
                          ai-lab namespace (default-deny NetworkPolicy)
  ┌──────────────────────────────────────────────────────────────────────┐
  │                                                                        │
  │   ┌───────────┐  MCP (HTTP :8000)   ┌───────────────┐                  │
  │   │ HolmesGPT │ ───────────────────►│  grafana-mcp  │ ──► Grafana      │
  │   │  (agent)  │ ───────────────────►│  argocd-mcp   │ ──► Argo CD API   │
  │   │           │                     └───────────────┘                  │
  │   │           │  OTLP :4317                                            │
  │   │           │ ──────────────► ┌────────────────┐                     │
  │   └─────┬─────┘                 │ otel-collector │                     │
  │         │ K8s API (read, ai-lab)│  :4317 / :8889 │                     │
  │         ▼                       └───────┬────────┘                     │
  │   kube-apiserver                        │ metrics :8889  │ traces :4317 │
  └─────────────────────────────────────────┼────────────────┼────────────┘
                  egress 443 (LLM)           │                │
                  ──────────────►            ▼                ▼
            Anthropic API            Prometheus (scrape)   Tempo (monitoring)
                                            └──────────► Grafana dashboards ◄┘
```

- **Investigation path:** Holmes plans → calls MCP tools (Grafana for metrics/logs,
  Argo CD for sync state) and the read-only Kubernetes toolset (ai-lab only) → returns
  a diagnosis. It never connects to Postgres; DB health comes from Grafana metrics.
- **Telemetry path:** Holmes (LiteLLM OTel exporter) → OTel Collector → metrics to
  Prometheus (`:8889` scrape) + traces to Tempo (`:4317`) → Grafana.

---

## 4. The security model

| Control | How it's enforced | File |
|---|---|---|
| No cluster-scoped resources | `AppProject.clusterResourceWhitelist: []` + ClusterRole/Binding blacklisted | `argocd/ai-lab-appproject.yaml` |
| Namespaced RBAC only | `Role`+`RoleBinding` in `ai-lab`; chart `rbac.create: false` | `ai-lab/holmes/base/role.yaml`, `rolebinding.yaml` |
| Secret isolation | **Namespaced** `SecretStore` → *separate* ai-lab Key Vault (cannot read prod secrets) | `ai-lab/secretstore/base/secretstore.yaml` |
| Read-only Grafana | Viewer-role token **and** `--disable-write` | `ai-lab/mcp-grafana/base/deployment.yaml` |
| Read-only Argo CD | `holmes-readonly` account RBAC **and** `MCP_READ_ONLY=true` | `ai-lab/mcp-argocd/base/deployment.yaml` |
| Network containment | default-deny + explicit egress; **no rule to `cnpg-prod`**; LLM egress excludes RFC1918 | `ai-lab/holmes/base/networkpolicy.yaml` |
| Blast-radius cap | `ResourceQuota` on `ai-lab` | `ai-lab/holmes/base/resourcequota.yaml` |
| No shell / no remediation | `bash` toolset disabled; no write MCP; minimal toolsets | `ai-lab/holmes/overlays/prod/holmes-values.yaml` |

**Why cross-namespace K8s reads are intentionally absent:** the `AppProject` only
permits the `ai-lab` namespace as a destination, so RoleBindings cannot be created in
`cnpg-prod`/`monitoring` from this track. The agent therefore sees other namespaces
*only* through the Grafana and Argo CD MCP servers (metrics + GitOps state) — which is
the safer design. If you ever want direct K8s reads of another namespace, create that
RoleBinding by hand, outside this project (see §10).

---

## 5. File map of the AI-lab track

```
argocd/
  ai-lab-appproject.yaml            # trust boundary (AppProject)
  ai-lab-applicationset.yaml        # discovers ai-lab/*/overlays/prod
  ai-lab-holmes-application.yaml    # standalone Helm Application (ai-lab-holmes-chart)

ai-lab/
  secretstore/      base/{secretstore.yaml,kustomization.yaml} + overlays/prod
  mcp-grafana/      base/{deployment,service,external-secret,kustomization} + overlays/prod
  mcp-argocd/       base/{deployment,service,external-secret,kustomization} + overlays/prod
  otel-collector/   base/{configmap,deployment,service,servicemonitor,kustomization} + overlays/prod
  holmes/
    base/{external-secret,networkpolicy,skills-configmap,resourcequota,role,rolebinding,kustomization}
    overlays/prod/{holmes-values.yaml,kustomization.yaml}
    dashboards/holmes-agent-dashboard.json   # import artifact (not synced)

infrastructure/tempo/   base/{configmap,pvc,deployment,service,grafana-datasource,kustomization} + overlays/prod

modules/argocd-infrastructure/main.tf   # EDITED: bootstraps the 3 argocd/ai-lab-*.yaml via file()
```

**ArgoCD applications that result:**
- `ai-lab-secretstore`, `ai-lab-mcp-grafana`, `ai-lab-mcp-argocd`,
  `ai-lab-otel-collector`, `ai-lab-holmes` (support manifests) — from the ApplicationSet.
- `ai-lab-holmes-chart` — the Helm release (standalone Application).
- `infra-tempo-prod` — from the existing infrastructure ApplicationSet.

---

## 6. Configuration reference (every TODO)

Search the tree for markers: `grep -rn 'TODO(amine' ai-lab infrastructure/tempo argocd`.

### 6.1 Secrets you create in the **ai-lab Key Vault**

| Key Vault secret | Consumed by (ExternalSecret → K8s Secret) | What it is |
|---|---|---|
| `grafana-mcp-viewer-token` | `grafana-mcp-token` | Grafana **Viewer** service-account token |
| `argocd-mcp-readonly-token` | `argocd-mcp-token` | Argo CD API token for the `holmes-readonly` account |
| `holmes-anthropic-api-key` | `holmes-llm-secret` | LLM API key |

### 6.2 SecretStore (`ai-lab/secretstore/base/secretstore.yaml`)
- `vaultUrl` → the **separate** ai-lab Key Vault URL.
- `tenantId` → Azure tenant id (prod uses `8052b405-…`; confirm whether you reuse it).
- `authSecretRef` → reads K8s secret `ai-lab-azure-sp` (keys `client-id`/`client-secret`)
  **in the `ai-lab` namespace** — created by Terraform (see §7.1).

### 6.3 Image & version pins (replace `:latest`)
| File | Pin |
|---|---|
| `ai-lab/mcp-grafana/base/deployment.yaml` | `mcp/grafana@sha256:…` |
| `ai-lab/mcp-argocd/base/deployment.yaml` | `ghcr.io/argoproj-labs/argocd-mcp@sha256:…` |
| `ai-lab/otel-collector/base/deployment.yaml` | `otel/opentelemetry-collector-contrib@sha256:…` |
| `infrastructure/tempo/base/deployment.yaml` | `grafana/tempo:<version>` |
| `argocd/ai-lab-holmes-application.yaml` | `targetRevision` = holmes chart version |

### 6.4 Holmes values (`ai-lab/holmes/overlays/prod/holmes-values.yaml`)
- **Model id:** `anthropic/claude-sonnet-4-5` → confirm current (`claude-sonnet-4-6` /
  `claude-opus-4-8`).
- **RBAC keys:** `rbac.create: false` + `serviceAccount.name: holmes` — verify these
  exact keys against `helm show values robusta/holmes --version <v>`. If the chart still
  emits a `ClusterRole`, the sync will be **rejected** by the AppProject.

### 6.5 Other pins
- `ai-lab/holmes/base/networkpolicy.yaml` → MicroK8s kube-apiserver ClusterIP
  (`10.152.183.1/32` is the MicroK8s default; confirm yours).
- `ai-lab/holmes/base/rolebinding.yaml` → ServiceAccount name must match 6.4.
- `ai-lab/otel-collector/base/servicemonitor.yaml` → `release` label your Prometheus
  operator selects on, and confirm Prometheus watches the `ai-lab` namespace.
- `ai-lab/holmes/base/resourcequota.yaml`, `infrastructure/tempo/base/pvc.yaml` →
  sizes/retention.

---

## 7. Bootstrap & deploy order

### 7.1 Manual prerequisites (do first, by hand)

These are outside the file-authoring scope and gate everything.

1. **Terraform — ai-lab Key Vault + SP secret.** Add an `azure-keyvault` +
   `azure-secrets` invocation (mirror the prod pattern) for a *separate* ai-lab vault,
   and create the `ai-lab-azure-sp` K8s secret (`client-id`/`client-secret`) **in the
   `ai-lab` namespace**. Fill `vaultUrl`/`tenantId` (6.2).
2. **Create the three Key Vault secrets** (6.1).
3. **Grafana:** create a Viewer service account + token → store as
   `grafana-mcp-viewer-token`.
4. **Argo CD:** add to `argocd-cm`: `accounts.holmes-readonly: apiKey`; to
   `argocd-rbac-cm`:
   ```
   p, role:holmes-readonly, applications, get, */*, allow
   p, role:holmes-readonly, applications, list, */*, allow
   g, holmes-readonly, role:holmes-readonly
   ```
   Generate its API token → store as `argocd-mcp-readonly-token`.
5. **Fill the remaining pins** in §6.

### 7.2 Sync waves (already annotated)

Per app, credentials precede consumers:
`SecretStore` (wave **-2**) → `ExternalSecret`s (wave **-1**) → Deployments / chart (wave **0**).

### 7.3 Commit & apply sequence

ArgoCD only starts after the Terraform-bootstrapped `kubectl_manifest` resources apply
the AppProject/ApplicationSet/Application. **`terraform apply` is the real trigger.**

1. **Tempo first (independent):** commit `infrastructure/tempo/`. The existing infra
   ApplicationSet syncs `infra-tempo-prod` into `monitoring`. Verify healthy.
2. **Do the §7.1 prerequisites.**
3. **Commit** the `ai-lab/` tree, the three `argocd/ai-lab-*.yaml`, and the module edit;
   then **`terraform apply environments/shared`**. This applies the AppProject →
   ApplicationSet → Holmes Application; ArgoCD syncs each app in wave order.

---

## 8. Testing & verification

Prefer the **ArgoCD UI** and **Grafana** for verification. Any `kubectl` below is
**read-only** and must be run by you on the homelab context (this repo treats the
cluster as off-limits to automation).

### 8.1 Stage-by-stage (ArgoCD UI)
1. `infra-tempo-prod` → **Synced / Healthy**; Grafana shows a **Tempo** datasource.
2. After TF apply, these apps appear: `ai-lab-secretstore`, `ai-lab-mcp-grafana`,
   `ai-lab-mcp-argocd`, `ai-lab-otel-collector`, `ai-lab-holmes`, `ai-lab-holmes-chart`.
3. Open `ai-lab-secretstore` → the `SecretStore` resource is **Healthy** (ESO validated
   the SP). If **Degraded**, the vault/SP config (6.2 / 7.1) is wrong — fix before going on.
4. Each `ExternalSecret` shows its target `Secret` created (`grafana-mcp-token`,
   `argocd-mcp-token`, `holmes-llm-secret`).
5. `ai-lab-holmes-chart` → **Synced / Healthy** = agent is up.

### 8.2 Read-only smoke checks (you run these)
```bash
# Pods healthy in the isolated namespace
kubectl get pods -n ai-lab

# ExternalSecrets resolved (SecretStore reachable, secrets materialised)
kubectl get externalsecrets,secretstore -n ai-lab

# MCP servers answer (from inside the namespace; no ingress is exposed by design)
kubectl -n ai-lab exec deploy/holmes -- wget -qO- http://grafana-mcp:8000/healthz || true

# Telemetry is flowing: collector is scraped and Tempo is receiving
kubectl get servicemonitor -n ai-lab
kubectl get pods -n monitoring -l app=tempo
```

### 8.3 Functional test of the agent
Run an investigation (via the Holmes CLI/UI per the chart's access method) such as
*"why is the linkding app degraded?"* and confirm:
- It uses the **Grafana** and **Argo CD** MCP tools (not direct DB access).
- It refuses to propose `kubectl`/imperative fixes (skills enforce GitOps posture).

### 8.4 Observability test
In Grafana: import `ai-lab/holmes/dashboards/holmes-agent-dashboard.json` (Dashboards →
Import). After an investigation you should see token usage, latency p50/p95, tool-call
counts by MCP server, and error rate. In **Tempo**, open the trace for the investigation
and confirm child spans for each LLM call and MCP tool invocation.

### 8.5 Security assertions to confirm
- The agent **cannot** reach `cnpg-prod` Postgres (no NetworkPolicy egress to it).
- Grafana/Argo CD MCP tools expose **no** write/sync/delete operations.
- The `ai-lab` `SecretStore` cannot read any production Key Vault secret (separate vault).

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `ai-lab-holmes-chart` sync **rejected**: cluster resource not permitted | Holmes chart created a `ClusterRole` | Set the chart's RBAC-disable key correctly (6.4); rely on the namespaced `Role`/`RoleBinding` |
| `SecretStore` **Degraded** / ExternalSecrets not resolving | wrong `vaultUrl`/`tenantId`, or `ai-lab-azure-sp` secret missing in `ai-lab` | Fix 6.2 / 7.1 |
| Agent metrics absent in Grafana | Prometheus not selecting the ai-lab `ServiceMonitor` | Set `release` label + Prometheus namespace selector (6.5) |
| No traces in Tempo | collector→Tempo egress blocked or Tempo down | Confirm `ai-lab-otel-egress` policy + `infra-tempo-prod` healthy |
| MCP calls fail from Holmes | NetworkPolicy ingress/egress mismatch | Check `ai-lab-mcp-ingress` / `ai-lab-holmes-egress` labels (`mcp-server: "true"`) |
| Argo CD MCP TLS errors | self-signed in-cluster cert | `NODE_TLS_REJECT_UNAUTHORIZED=0` is set; prefer a real CA later |
| Holmes can't read other namespaces | by design (namespaced RBAC only) | Use Grafana/Argo CD MCP, or add a RoleBinding out-of-band (§10) |

---

## 10. Day-2 operations

- **Rotate tokens:** update the secret in the ai-lab Key Vault; ESO refreshes within
  `refreshInterval` (1h). No redeploy needed.
- **Upgrade the agent:** bump `targetRevision` in `argocd/ai-lab-holmes-application.yaml`
  (reconcile values keys), or the image digests for the MCP servers / collector / Tempo.
- **Temporarily disable:** suspend auto-sync on the ai-lab apps in the ArgoCD UI, or set
  Holmes `replicas: 0` via values. The trust boundary stays intact.
- **Widen K8s visibility (conscious choice):** to let Holmes read another namespace
  directly, create a `Role`+`RoleBinding` for the `holmes` ServiceAccount **in that
  namespace** (committed under that app's overlay, default project) — not via the ai-lab
  project, which forbids it.
- **Add remediation later (with care):** keep GitOps as the single write path — the agent
  proposes a change as a Git commit/PR via a write-capable MCP, and a human approves the
  merge. Never flip the MCP servers off read-only.

---

### Cross-references
- Architecture: `docs/architecture/overview.md`
- Backups & DR: `docs/operations/backup-restore.md`, `docs/operations/disaster-recovery.md`
- Bootstrap: `docs/bootstrap/01-new-cluster-bootstrap.md`
- Troubleshooting (cluster): `docs/operations/troubleshooting.md`
