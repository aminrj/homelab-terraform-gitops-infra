#!/usr/bin/env bash
#
# Provision the threat intelligence read-only datasource in Grafana.
# Requirements:
#   * GRAFANA_BASE_URL  (e.g. https://grafana.lab.example.com)
#   * GRAFANA_API_TOKEN (Service account token with datasource:write)
#   * PG_HOST           (e.g. pg-prod-rw.cnpg-prod.svc.cluster.local)
#   * PG_DATABASE       (default threatintel)
#   * PG_USER / PG_PASSWORD (read-only credentials)
set -euo pipefail

for var in GRAFANA_BASE_URL GRAFANA_API_TOKEN PG_HOST PG_DATABASE PG_USER PG_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required variable: ${var}" >&2
    exit 1
  fi
done

datasource_payload=$(
  jq -n \
    --arg name "Threat Intel" \
    --arg host "${PG_HOST}" \
    --arg database "${PG_DATABASE}" \
    --arg user "${PG_USER}" \
    --arg password "${PG_PASSWORD}" \
    '{
      name: $name,
      type: "postgres",
      typeLogoUrl: "",
      access: "proxy",
      isDefault: false,
      basicAuth: false,
      jsonData: {
        database: $database,
        sslmode: "disable",
        postgresVersion: 1500,
        timescaledb: false
      },
      secureJsonData: {
        password: $password
      },
      user: $user,
      url: ($host + ":5432")
    }'
)

echo "Creating/updating Grafana datasource 'Threat Intel'..."
curl -fsSL \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
  -X POST \
  --data "${datasource_payload}" \
  "${GRAFANA_BASE_URL%/}/api/datasources"

echo "Datasource provisioned."
