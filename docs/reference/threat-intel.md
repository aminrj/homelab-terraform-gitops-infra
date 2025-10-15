# Threat Intelligence Automation Platform

This document describes how the `threat-intel` namespace ties together CloudNativePG, n8n workflows, and Azure storage to deliver the threat intelligence pipeline defined in `apps/threat-intell/project-prd.md`.

## Components

- **Kubernetes namespace:** `threat-intel` (managed by ArgoCD via `apps/threat-intell/overlays/prod`).
- **Database:** Dedicated CloudNativePG cluster `threat-intel-db-cnpg-v1` (defined under `databases/threat-intell/`) with daily scheduled backups.
- **Schema reconciler:** `CronJob/threat-intel-schema-reconcile` keeps tables under the `threatintel` schema present.
- **Secrets:** Sourced from Azure Key Vault through ExternalSecrets (`threat-intel-db-creds`, `threat-intel-db-storage`, `threat-intel-api-keys`, `threat-intel-azure-storage`).
- **Azure storage:** Containers `threat-intel-db-clean` (database backups) and `threatintel-data` (workflow exports).
- **n8n workflows:** Five version-controlled exports stored under `apps/threat-intell/workflows/` covering collection, baseline extraction, LLM extraction, enrichment, and export.
- **Automation helper:** `Deployment/threat-intel-automation` (plus services) accepts workflow callbacks for metrics, enrichment stubs, and export acknowledgements.
- **Grafana dashboard:** `grafana/dashboard-threatintel.json` visualises extraction/enrichment metrics and exposes a Postgres panel using the read-only datasource `threat-intel-ro`.
- **Evaluation tooling:** `apps/threat-intell/evaluate.py` computes precision/recall and latency aggregates from labeled data.

## Required One-Off Steps

1. **Provision database user/schema**
   - Apply Terraform for the environment; it now creates the dedicated CNPG cluster, the `threat-intel-db-clean` storage container, and Key Vault entries (`threat-intel-db-username`, `threat-intel-db-name`, `threat-intel-db-password`).
   - When ArgoCD reconciles `databases/threat-intell/overlays/prod`, the cluster bootstraps via `initdb` using those credentials. No manual SQL is required.

2. **Populate API credentials**
   - After Terraform completes, populate the optional provider keys in Azure Key Vault using the expected names (`threat-intel-vt-api-key`, `threat-intel-shodan-api-key`, `threat-intel-abuseipdb-api-key`, `threat-intel-openai-api-key`, `threat-intel-ollama-host`, `threat-intel-azure-container`). External Secrets will mirror them into the namespace.

3. **Import workflows into n8n**
   - Preferred: run `scripts/threat-intel/import-workflows.sh` after setting `N8N_BASE_URL` + `N8N_API_KEY` (requires `jq` and `curl`).
   - Alternatively, import each JSON file in `apps/threat-intell/workflows/` via *n8n → Workflows → Import from File*.
   - Adjust credential references inside n8n to point at the newly created database/API keys. All workflow exports expect credentials named:
     - `threat-intel-db` (Postgres)
     - `openai-threat-intel` (HTTP header auth)
     - `threat-intel-api-gateway` / `threat-intel-exporter` (internal services or HTTP auth placeholders)

4. **Create Grafana datasource**
   - Run `scripts/threat-intel/provision-grafana-datasource.sh` after exporting `GRAFANA_BASE_URL`, `GRAFANA_API_TOKEN`, `PG_HOST`, `PG_DATABASE`, `PG_USER`, and `PG_PASSWORD`.
   - Import `grafana/dashboard-threatintel.json` and place it in the "Threat Intel" folder.

## Operations Notes

- The schema cron job runs every six hours; it is idempotent and safe to leave in place.
- `Deployment/threat-intel-automation` provides stub responses plus `/metrics` output for Prometheus scraping. Replace it with real services when production integrations are ready.
- Use `apps/threat-intell/evaluate.py --json metrics.json` to export evaluation results for reports or dashboards.
- Azure exports are written to `threatintel-data/threat-intel/exports/…`. Rotate SAS tokens by reapplying Terraform (`environments/prod`) when needed.

## Future Enhancements

- Replace the placeholder automation deployment with dedicated microservices or n8n webhook workflows.
- Add a read-only service account for Grafana and data science notebooks.
- Extend evaluation to compute per-provider SLAs and enrichment latency percentiles directly in Prometheus.
