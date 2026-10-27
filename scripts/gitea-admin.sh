#!/usr/bin/env bash
# Gitea bootstrap (homelab-foundation docs/assistant.md, runbook step C).
#
#   scripts/gitea-admin.sh secrets         # create the missing Gitea secrets in Key Vault (random values)
#   scripts/gitea-admin.sh admin           # create your admin user in the running pod (once)
#
# Make targets: `make gitea-secrets`, `make gitea-admin`. Values are never printed; the admin
# password lands in Key Vault (gitea-admin-password) for your password manager.
set -euo pipefail
cd "$(dirname "$0")/.."
KEY_VAULT_NAME=${KEY_VAULT_NAME:-$(sed -n 's/^KEY_VAULT_NAME=//p' ../homelab-foundation/.env 2>/dev/null)}
: "${KEY_VAULT_NAME:?set KEY_VAULT_NAME}"
ADMIN_USER=${GITEA_ADMIN_USER:-amine}
ADMIN_EMAIL=${GITEA_ADMIN_EMAIL:-amine@gitea.local}

has() { az keyvault secret show --vault-name "$KEY_VAULT_NAME" -n "$1" --query id -o tsv >/dev/null 2>&1; }
put_random() {
  local f; f=$(mktemp); chmod 600 "$f"
  if [ -n "${2:-}" ]; then printf '%s' "$2" > "$f"; else head -c 48 /dev/urandom | base64 | tr -d '/+=\n' | head -c 48 > "$f"; fi
  az keyvault secret set --vault-name "$KEY_VAULT_NAME" -n "$1" --file "$f" --encoding utf-8 -o none \
    --description "Gitea (GitOps scripts/gitea-admin.sh)"
  head -c 4096 /dev/urandom > "$f"; rm -f "$f"
}

case "${1:-}" in
  secrets)
    for pair in gitea-db-username:gitea gitea-db-name:gitea gitea-db-password: gitea-secret-key: gitea-internal-token: gitea-admin-password:; do
      name=${pair%%:*} fixed=${pair#*:}
      if has "$name"; then echo "ok: $name"; else put_random "$name" "$fixed"; echo "created: $name"; fi
    done
    ;;
  admin)
    pod=$(kubectl -n gitea-prod get pod -l app=gitea -o jsonpath='{.items[0].metadata.name}')
    if kubectl -n gitea-prod exec "$pod" -- su git -c "gitea admin user list --admin" 2>/dev/null | awk 'NR>1{print $2}' | grep -qx "$ADMIN_USER"; then
      echo "ok: admin user $ADMIN_USER exists"; exit 0
    fi
    pw=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" -n gitea-admin-password --query value -o tsv)
    # The password reaches the pod on stdin, not on a command line.
    printf '%s' "$pw" | kubectl -n gitea-prod exec -i "$pod" -- sh -c \
      "read -r p; su git -c \"gitea admin user create --admin --username '$ADMIN_USER' --email '$ADMIN_EMAIL' --password \\\"\$p\\\" --must-change-password=false\""
    unset pw
    echo "created admin $ADMIN_USER; password: Key Vault gitea-admin-password. Next: sign in, Settings > Applications,"
    echo "create a token with all scopes and store it: (homelab-foundation) make secret-set NAME=gitea-admin-token"
    ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
