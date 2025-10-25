# Documentation about the Threat Intelligence Platform

## Details about existing workflows

- apps/threat-intell/workflows/collector-open-source.json:
  every 3 h hits CISA KEV, AlienVault OTX, CERT-EU, normalizes entries, stores them
  in threatintel.raw_doc, and posts a collector metric.
- apps/threat-intell/workflows/baseline-extractor.json:
  nightly regex extractor over recent docs; writes baseline IOCs to threatintel.ioc
  and reports extractor counts.
- apps/threat-intell/workflows/llm-extractor.json:
  hourly LLM pass using gpt-4o-mini; parses structured IOC JSON, upserts into
  threatintel.ioc, and tracks hallucination stats.
- apps/threat-intell/workflows/enrichment-pipeline.json:
  every 2 h batches pending IOCs, calls the internal enrichment gateway, upserts
  provider results into threatintel.enrichment, and emits enrichment metrics.
- apps/threat-intell/workflows/validator-export.json:
  daily 05:00 UTC scoring/exporter; composes final candidate scores, uploads the
  validated CSV, and reports validator metrics.
- apps/n8n/workflows/feed-summarizer-via-ollama.json:
  twice-daily Hacker News RSS summary via Ollama and Telegram push (not part of threat-
  intell but useful for ops updates).

## Importing the n8n workflows

n8n 1.75 tightened its import validation. Exports created on older versions were failing with
`propertyValues[itemName] is not iterable` because the Cron node schema now wraps `triggerTimes` in
an `item` object and the importer also expects the JSON payload to be an array of workflows. All
repository JSON files have been rewritten to use the new layout and to default the first node to a
`Manual Trigger` so the UI can open them before you add a new schedule.

To import the workflows into the running pod:

```bash
# Copy one workflow at a time (example for the collector)
kubectl cp apps/threat-intell/workflows/collector-open-source.json \
  n8n-prod/n8n-7d5b9cb6b8-6rct9:/tmp/collector-open-source.json

# Import inside the pod
kubectl exec -n n8n-prod n8n-7d5b9cb6b8-6rct9 -- \
  n8n import:workflow --input /tmp/collector-open-source.json
```

Repeat the copy/import pairing for:

- `apps/threat-intell/workflows/enrichment-pipeline.json`
- `apps/threat-intell/workflows/baseline-extractor.json`
- `apps/threat-intell/workflows/llm-extractor.json`
- `apps/threat-intell/workflows/validator-export.json`
- `apps/n8n/workflows/feed-summarizer-via-ollama.json`

After each import, open the workflow in the UI, map credentials, and replace the temporary Manual
Trigger with the desired Cron schedule (the editor now serialises the node in the correct 1.75
format). Save and enable once the test run succeeds.

## Provisioning the threat-intel database credentials

1. **Create the `n8n_collector` role in CNPG**
   ```bash
   kubectl -n threat-intel port-forward svc/threat-intel-db-rw 5432:5432
   PGPASSWORD=<admin_password> psql -h 127.0.0.1 -p 5432 -U <admin_user> threatintel
   ```
   Inside `psql`:
   ```sql
   CREATE USER n8n_collector WITH PASSWORD '<strong password>';
   GRANT USAGE ON SCHEMA threatintel TO n8n_collector;
   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA threatintel TO n8n_collector;
   GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA threatintel TO n8n_collector;
   GRANT CREATE ON SCHEMA threatintel TO n8n_collector;
   ALTER DEFAULT PRIVILEGES IN SCHEMA threatintel
     GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO n8n_collector;
   ALTER DEFAULT PRIVILEGES IN SCHEMA threatintel
     GRANT USAGE, SELECT ON SEQUENCES TO n8n_collector;
   \q
   ```

2. **Apply Terraform (prod environment)**
   - Adds the `threat-intel-n8n-db-*` secrets to Key Vault
   - Generates `threat-intel-n8n-db-password`
   ```bash
   cd environments/prod
   terraform init
   terraform apply
   ```
   Update the database user to use the generated password:
   ```sql
   ALTER USER n8n_collector WITH PASSWORD '<value of threat-intel-n8n-db-password>';
   ```

3. **Deploy the n8n ExternalSecret and refresh the pod**
   ```bash
   kubectl apply -k apps/n8n/overlays/prod
   kubectl -n n8n-prod rollout restart deployment/n8n
   ```

4. **Create the Postgres credential in n8n**
   - Host: `={{ $env('N8N_TI_DB_HOST') }}`
   - Database: `={{ $env('N8N_TI_DB_NAME') }}`
   - User: `={{ $env('N8N_TI_DB_USER') }}`
   - Password: `={{ $env('N8N_TI_DB_PASS') }}`
   - Port: `5432`

5. **Wire the credential into the collector workflow** (Postgres node with the upsert query).
