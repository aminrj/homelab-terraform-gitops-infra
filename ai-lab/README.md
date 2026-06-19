# ai-lab/ — Observable read-only AI-SRE agent (HolmesGPT)

This track deploys a **read-only** HolmesGPT SRE agent with Grafana + Argo CD MCP
servers, custom skills, and full OpenTelemetry agent telemetry — isolated in its own
namespace, ArgoCD `AppProject`, Key Vault scope, and default-deny network.

**Read the full guide before touching anything:**
[`docs/ai-lab/holmesgpt-agent.md`](../docs/ai-lab/holmesgpt-agent.md)
— architecture, security model, every `TODO(amine: …)`, bootstrap order, and
testing/verification.

## Layout

| Dir | What |
|---|---|
| `secretstore/` | Namespaced `SecretStore` → separate ai-lab Key Vault |
| `mcp-grafana/` | Grafana MCP server (read-only: Viewer token + `--disable-write`) |
| `mcp-argocd/` | Argo CD MCP server (read-only: `holmes-readonly` + `MCP_READ_ONLY=true`) |
| `otel-collector/` | Receives agent telemetry → Prometheus + Tempo |
| `holmes/` | Agent support manifests + Helm values + dashboard artifact |

The Tempo backend lives in `infrastructure/tempo/` (namespace `monitoring`). The three
ArgoCD manifests are in `argocd/ai-lab-*.yaml`, bootstrapped by the
`argocd-infrastructure` Terraform module.

> Nothing here is applied by hand. Terraform applies the AppProject/ApplicationSet;
> ArgoCD syncs the rest from `main`. See the guide's "Bootstrap & deploy order".
