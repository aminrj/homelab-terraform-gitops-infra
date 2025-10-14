# 🧩 Product Requirements Document (PRD)

## Threat Intelligence Automation & Research Platform

**Version:** 1.0
**Author:** [Your Name]
**Date:** October 2025
**Status:** Draft — for development and experimentation

---

## 1. 🧠 Executive Summary

This document defines the design and implementation plan for integrating a **Threat Intelligence Automation Platform** into the existing homelab infrastructure.

The platform will:

- Continuously **collect, enrich, and analyze threat intelligence data (IOCs, CVEs, OSINT)** from public sources.
- Use **n8n** as the orchestration engine for all automation tasks, providing visual workflows.
- Store all structured data in the existing **CloudNativePG (PostgreSQL)** database cluster.
- Archive and export datasets and reports to existing **Azure Blob Storage**.
- Deploy declaratively through **ArgoCD** following GitOps principles.
- Serve as a **foundation for applied cybersecurity + AI research**, enabling publication-quality experiments.

This addition will leverage 100% of the existing observability, CI/CD, and storage components — introducing only a new **namespace, schema, and set of workflows**.

---

## 2. 🎯 Goals & Objectives

### Primary Goals

1. **Automate threat intelligence collection & enrichment** using reproducible, modular n8n workflows.
2. **Build a central CTI database** (schema `threatintel`) storing raw, extracted, and enriched IOCs.
3. **Enable AI-assisted extraction** of IOCs using LLMs (IntelEX-inspired pipeline).
4. **Provide dashboards and alerts** in Grafana for data quality, enrichment coverage, and feed health.
5. **Publish research-ready datasets and analysis pipelines**, aligning with recent CTI literature benchmarks (CTIBench, LLM-TIKG, IntelEX).

### Long-term Objectives

- Develop a **knowledge graph** linking indicators, actors, malware, and CVEs.
- Train or fine-tune local LLMs for CTI summarization and extraction.
- Produce periodic **research papers and public reports** based on collected data.
- Offer APIs or feeds to the broader cybersecurity community.

---

## 3. 🏗️ Current Infrastructure Context

| Component                | Description                                    | Status         |
| ------------------------ | ---------------------------------------------- | -------------- |
| **Kubernetes Cluster**   | Primary execution environment                  | ✅ operational |
| **ArgoCD**               | GitOps controller (apps under `gitops/apps/`)  | ✅ operational |
| **CloudNativePG (CNPG)** | PostgreSQL operator for app data               | ✅ in use      |
| **Grafana + Prometheus** | Observability stack                            | ✅ in use      |
| **n8n**                  | Workflow automation orchestrator               | ✅ in use      |
| **Azure Storage**        | Central storage for backups, exports, archives | ✅ in use      |
| **Listmonk**             | Newsletter & reporting system                  | ✅ in use      |
| **Commafeed**            | RSS aggregation for feeds                      | ✅ in use      |

The new **Threat Intelligence App** will be an additional ArgoCD-managed namespace (`threat-intel`) that extends these services.

---

## 4. 🧩 System Architecture Overview

### Logical Architecture

```
              ┌────────────────────────────┐
              │         ArgoCD             │
              │ (GitOps: Deploy everything)│
              └────────────┬───────────────┘
                           │
        ┌──────────────────┴───────────────────────┐
        │                  K8s                     │
        │                                           │
        │  ┌─────────────┐   ┌──────────────────┐   │
        │  │ n8n         │ → │ ThreatIntel DB   │   │
        │  │ (Workflows) │   │ (CNPG schema)    │   │
        │  └──────┬──────┘   └───────┬──────────┘   │
        │          │                 │              │
        │  ┌───────▼──────┐   ┌──────▼─────────┐   │
        │  │ LLM Extractor │   │ Enrichment API │   │
        │  │ (OpenAI/Ollama)│  │  (VT, Shodan)  │   │
        │  └───────┬──────┘   └────────┬────────┘   │
        │          │                   │            │
        │          ▼                   ▼            │
        │   Azure Blob Storage ←─── n8n Exporter    │
        │   (raw + enriched data)                   │
        └───────────────────────────────────────────┘
```

---

## 5. 🔁 Nominal Workflow

| Step                       | Description                                             | Automation          | Output                               |
| -------------------------- | ------------------------------------------------------- | ------------------- | ------------------------------------ |
| **1. Collection**          | Collect RSS feeds & CTI reports                         | n8n cron workflow   | `raw_doc` table                      |
| **2. Baseline Extraction** | Parse IOCs via regex & parser libraries                 | n8n workflow        | `ioc` table (`extractor='baseline'`) |
| **3. LLM Extraction**      | Use LLM to extract IOCs from unstructured text          | n8n + LLM API       | `ioc` table (`extractor='llm'`)      |
| **4. Enrichment**          | Validate & enrich IOCs via VT, Shodan, Whois, AbuseIPDB | n8n orchestrator    | `enrichment` table                   |
| **5. Validation**          | Compute composite score, flag validated IOCs            | n8n logic node      | `final_candidates` table             |
| **6. Export**              | Upload JSON/CSV summaries to Azure & trigger reports    | n8n export workflow | Azure Blob + Listmonk email          |
| **7. Visualization**       | Grafana dashboards auto-refresh from CNPG               | Grafana             | IOC metrics & trends                 |

---

## 6. 🗃️ Data Model (CNPG Schema)

```sql
CREATE SCHEMA IF NOT EXISTS threatintel;

CREATE TABLE threatintel.raw_doc (
  id UUID PRIMARY KEY,
  source TEXT,
  url TEXT,
  title TEXT,
  raw_text TEXT,
  collected_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE threatintel.ioc (
  id UUID PRIMARY KEY,
  doc_id UUID REFERENCES threatintel.raw_doc(id),
  extractor TEXT, -- baseline | llm
  ioc_type TEXT,  -- ip/domain/url/hash/cve
  value TEXT,
  evidence_span TEXT,
  extracted_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE threatintel.enrichment (
  id UUID PRIMARY KEY,
  ioc_id UUID REFERENCES threatintel.ioc(id),
  provider TEXT, -- virustotal | shodan | whois | abuseipdb
  result JSONB,
  validated BOOLEAN,
  checked_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE threatintel.labels (
  id UUID PRIMARY KEY,
  ioc_id UUID REFERENCES threatintel.ioc(id),
  annotator TEXT,
  label TEXT, -- TP | FP | UNKNOWN
  confidence INT,
  labeled_at TIMESTAMP DEFAULT NOW()
);
```

---

## 7. ⚙️ Technical Requirements

| Category            | Requirement                                                                                                                              |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **Automation**      | All collection, enrichment, and export tasks must be implemented as **n8n workflows**. No external cronjobs or scripts unless necessary. |
| **Orchestration**   | Each n8n workflow is version-controlled (exported JSON committed to Git). ArgoCD deploys via config import job.                          |
| **Database**        | Use existing CNPG cluster. Create new schema `threatintel` only. No new clusters.                                                        |
| **Storage**         | Use existing Azure Blob Storage account; create new container `threatintel-data`.                                                        |
| **Secrets**         | Use SealedSecrets or Azure KeyVault. Store API keys for VT, Shodan, AbuseIPDB, OpenAI.                                                   |
| **Observability**   | Expose Prometheus metrics via n8n stats and enrichment worker endpoints. Create Grafana dashboard.                                       |
| **Deployment**      | New K8s namespace: `threat-intel`. All manifests managed under `gitops/apps/threat-intel/`.                                              |
| **Security**        | Apply NetworkPolicy to restrict namespace. Read-only DB roles for Grafana and LLM API workers.                                           |
| **Reproducibility** | All workflows, schemas, evaluation scripts, and configs versioned in Git.                                                                |
| **Cost Control**    | Enrichment cache table; configurable TTLs for re-validation; use n8n rate-limit nodes.                                                   |

---

## 8. 🧠 LLM Prompt Template (for IOC Extraction)

**System Prompt**

```
You are a cybersecurity analyst who extracts Indicators of Compromise (IOCs) from reports.
Only output valid JSON: [{"type":"<ip|domain|url|hash|cve>","value":"<ioc>","evidence":"<quote from text>","confidence":<0-1>}]
If unsure, set low confidence. Never invent data.
```

**User Prompt**

```
Document:
<<<
{document_text}
>>>
Extract IOCs and evidence from the above text.
```

**Few-shot examples** will include normalized obfuscated IPs and CVEs for better consistency.

---

## 9. 🔍 Enrichment APIs (Validators)

| Provider       | Endpoint                 | Validation Logic                      | Notes         |
| -------------- | ------------------------ | ------------------------------------- | ------------- |
| **VirusTotal** | `/api/v3/{type}/{value}` | malicious_count > 0                   | Cache 30 days |
| **Shodan**     | `/shodan/host/{ip}`      | port/service match with known malware | Cache 7 days  |
| **AbuseIPDB**  | `/api/v2/check`          | abuseConfidenceScore > 50             | Cache 15 days |
| **Whois/RDAP** | `/rdap/domain/{domain}`  | privacy-proxy or <30 days old         | Cache 30 days |

All responses stored in `enrichment.result` JSONB and summarized in `enrichment.validated`.

---

## 10. 📊 Metrics & Dashboards

| Metric                            | Description                                          |
| --------------------------------- | ---------------------------------------------------- |
| `iocs_extracted_total{extractor}` | Total IOCs extracted per method                      |
| `enrichments_success_total`       | Successful enrichment API calls                      |
| `enrichment_error_total`          | Failed API calls                                     |
| `validated_iocs_total`            | Count of IOCs validated by enrichment                |
| `hallucination_rate`              | Fraction of LLM-extracted IOCs without evidence span |
| `label_queue_size`                | Pending items for human labeling                     |

**Grafana Dashboards:**

- IOC collection over time
- Feed freshness
- LLM vs Baseline extraction rate
- Enrichment success rate
- Validation confidence histogram

---

## 11. 🧪 Evaluation & Research Outputs

### Metrics

- **Precision, Recall, F1** per extractor (baseline vs LLM).
- **Hallucination Rate** = (FPs with no enrichment validation) / (total IOCs).
- **Enrichment Validation Rate** = (# IOCs validated by ≥1 provider) / total extracted.
- **Net Usable IOC Yield** = TP count post-validation per 1k docs.

### Scripts

`evaluate.py` connects to CNPG and computes metrics using human-labeled subset.

### Deliverables

- Clean labeled dataset (sanitized, aggregated).
- Evaluation code and workflow exports (for publication).
- Reproducibility documentation (ArgoCD manifests + sample data).

---

## 12. 🚀 Implementation Phases

| Phase                               | Duration | Deliverables                                   |
| ----------------------------------- | -------- | ---------------------------------------------- |
| **Phase 1** — Setup & Schema        | Week 1   | Namespace, DB schema, secrets, Azure container |
| **Phase 2** — Collector Workflow    | Week 2   | n8n workflow fetching & storing raw docs       |
| **Phase 3** — Baseline Extractor    | Week 3   | Regex parser workflow + metrics                |
| **Phase 4** — LLM Extractor         | Week 4–5 | LLM prompt + n8n API call workflow             |
| **Phase 5** — Enrichment Layer      | Week 6–7 | VT/Shodan integrations + cache logic           |
| **Phase 6** — Validation & Export   | Week 8   | Scoring + Azure export                         |
| **Phase 7** — Dashboards & Alerts   | Week 9   | Grafana + Prometheus metrics                   |
| **Phase 8** — Labeling & Evaluation | Week 10+ | Manual annotation + analysis scripts           |
| **Phase 9** — Paper Prep            | Week 12+ | Dataset release + publication draft            |

---

## 13. ⚠️ Risks & Mitigations

| Risk                | Impact            | Mitigation                                     |
| ------------------- | ----------------- | ---------------------------------------------- |
| API rate limits     | Delays enrichment | Implement caching, backoff, parallelization    |
| LLM hallucination   | False positives   | Require evidence spans + enrichment validation |
| Cost escalation     | API & token usage | Sample small subsets; local LLM via Ollama     |
| Data quality drift  | Degrades metrics  | Implement periodic re-evaluation               |
| Legal/TOS conflicts | Data-sharing risk | Publish only aggregated or anonymized data     |

---

## 14. ✅ Success Criteria

| Category          | Measure of Success                                            |
| ----------------- | ------------------------------------------------------------- |
| **Technical**     | 100% GitOps-managed deployment, 95% successful workflow runs  |
| **Data Quality**  | ≥0.85 precision, ≥0.70 recall (validated IOCs)                |
| **Observability** | Grafana dashboard shows real-time extraction/enrichment stats |
| **Research**      | Reproducible experiment repo + accepted workshop submission   |
| **Community**     | Weekly “Cyber Brief” newsletter generated from data           |

---

## 15. 📦 Deliverables

- `gitops/apps/threat-intel/` (K8s manifests, ArgoCD Application)
- `n8n/workflows/` (collector, baseline, LLM, enrichment, validator)
- `db/migrations/` (CNPG schema creation)
- `evaluate.py` (metrics computation)
- `grafana/dashboard-threatintel.json`
- `docs/prd-threat-intel-platform.md` (this document)

---

## 16. 🧩 Next Steps

1. Initialize repo folder `gitops/apps/threat-intel/` and commit base kustomization.
2. Create CNPG schema migration via Alembic.
3. Build `Collector` workflow in n8n (ingest & insert to `raw_doc`).
4. Implement Baseline extractor (regex) and LLM extractor (prompt + JSON).
5. Deploy enrichment orchestrator and Grafana dashboard.
6. Begin data collection for evaluation dataset.

---

### 📚 Reference Literature

- **CTIBench: A Benchmark for Evaluating LLMs in Cyber Threat Intelligence** — ArXiv 2024
- **IntelEX: LLM-driven Attack-level Threat Intelligence Extraction** — ArXiv 2024
- **LLM-TIKG: Knowledge Graph Construction for Threat Intelligence** — Elsevier 2024
- **Systematic Review of Cyber Threat Intelligence Research** — MDPI 2025
- **Recorded Future: Malicious Infrastructure Report 2024** — Insikt Group
