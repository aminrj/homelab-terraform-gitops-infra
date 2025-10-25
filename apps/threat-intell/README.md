# Documentation about the Threat Intelligence Platform

## Details about existing workflows

- apps/threat-intell/workflows/collector-open-source.json:
  every 3 h hits CISA KEV, AlienVault OTX, CERT-EU, normalizes entries, stores them
  in threatintel.raw_doc, and posts a collector metric.

  - Postgres insert uses positional parameters with JSON casting:

    ```sql
    INSERT INTO threatintel.raw_doc
      (source, source_key, url, title, raw_text, content_hash, metadata)
    VALUES ($1, $2, $3, $4, $5, $6, $7:json)
    ON CONFLICT (source, source_key)
    DO UPDATE SET
      raw_text     = EXCLUDED.raw_text,
      content_hash = EXCLUDED.content_hash,
      metadata     = EXCLUDED.metadata,
      collected_at = NOW();
    ```

    Query Parameters expression:

    ```javascript
    {
      {
        [
          $json.source,
          $json.source_key,
          $json.url ?? "",
          $json.title ?? "",
          $json.raw_text,
          $json.content_hash,
          $json.metadata ?? {},
        ];
      }
    }
    ```

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

## More details about the workflows

1. Collector (CISA KEV feed)
   - CISA publishes the “Known Exploited Vulnerability” catalog: a JSON list of CVEs, vendor/project, description, dates, etc.
   - The collector-open-source workflow fetches that feed, normalizes each entry into a document, and writes it into threatintel.raw_doc (one row per CVE).
   - Think of this as your raw threat intelligence feed—no indicators yet, just structured reports.
2. Extractors (Baseline + LLM)
   - The Baseline extractor combs the raw document for obvious indicators (IPs, domains, etc.) using regex, and writes them into threatintel.ioc.
   - The LLM extractor does a smarter pass: it queries an LLM, extracts potential IOCs with context, and also writes them into ioc.
   - After these workflows run, threatintel.ioc contains a list of indicators (value, type, source doc, extractor) that you can track.
3. Enrichment pipeline
   - Each IOC by itself isn’t that helpful—you want supporting context (score, reputation, provider verdicts).
   - The enrichment workflow picks IOCs from threatintel.ioc that haven’t been checked recently (or ever), calls your enrichment microservice (threat-intel-
     enrichment), and stores the results in threatintel.enrichment.
   - The enrichment service can combine external APIs (VirusTotal, Shodan, AbuseIPDB, RDAP, etc.) to enrich the IOC with additional metadata and confidence.
4. Validator & Exporter
   - Separately, the validator workflow aggregates enriched IOCs, scores them, selects the worthy ones, and exports them.
   - That gives you a final feed of vetted indicators (e.g., for sharing, alerts, or blocking rules).
5. Metrics & Grafana
   - Every workflow posts a small metric (collector/enrichment/extractor/validator), which you graph in Grafana to monitor the pipeline.

In short: CISA gives raw vulnerability reports, extractors turn those into concrete indicators, enrichment adds supporting evidence from external intel services,
and the validator/exporter prepares final outputs. To get the enrichment pipeline working you need IOCs first, so run the extractor workflow(s) next. Once there
are entries in threatintel.ioc, the enrichment query will start returning results.

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
