#!/usr/bin/env bash
# Set Grafana's admin password in its database to the one in Key Vault
# (gitops-grafana-admin-password, modules/admin-passwords). Grafana applies the chart's
# password only to a new database; run this after the password changes. Over stdin only.
#
#   make grafana-admin-sync
set -euo pipefail
: "${KEY_VAULT_NAME:?set KEY_VAULT_NAME (homelab-foundation .env)}"
K="kubectl --kubeconfig ${HOMELAB_KUBECONFIG:-$HOME/.kube/homelab} --context homelab -n monitoring"
az keyvault secret show --vault-name "$KEY_VAULT_NAME" -n gitops-grafana-admin-password --query value -o tsv \
  | $K exec -i deploy/kube-prometheus-stack-grafana -c grafana -- \
      grafana cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini admin reset-admin-password --password-from-stdin
echo "Grafana admin password set from Key Vault"
