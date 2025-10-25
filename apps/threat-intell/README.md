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
