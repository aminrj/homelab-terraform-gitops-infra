#!/usr/bin/env bash
#
# Import all threat intelligence workflows into an n8n instance.
# Requirements:
#   * N8N_BASE_URL - e.g. https://n8n.lab.example.com
#   * N8N_API_KEY  - Personal API token (Settings → API)
#   * Optional: set N8N_TAG to tag imported flows.
set -euo pipefail

if [[ -z "${N8N_BASE_URL:-}" || -z "${N8N_API_KEY:-}" ]]; then
  echo "N8N_BASE_URL and N8N_API_KEY must be set" >&2
  exit 1
fi

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../apps/threat-intell/workflows" && pwd)"
TAG="${N8N_TAG:-threat-intel}"

echo "Importing workflows from ${WORKFLOW_DIR}"

for file in "${WORKFLOW_DIR}"/*.json; do
  name="$(jq -r '.name' "${file}")"
  echo "→ importing ${name}"
  payload="$(jq --arg tag "${TAG}" '.tags = ([{"name": $tag}])' "${file}")"
  curl -fsSL \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -X POST \
    --data "${payload}" \
    "${N8N_BASE_URL%/}/rest/workflows"
done

echo "All workflows imported. Activate them in the UI as needed."
