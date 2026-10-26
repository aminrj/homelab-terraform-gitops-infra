#!/usr/bin/env bash
# On-demand CNPG backup to Azure (same object store as the hourly schedule), e.g. right
# before an app upgrade, and wait until it is completed.
#
#   make db-backup APP=n8n        # cluster <APP>-db-* in cnpg-prod
set -euo pipefail
APP=${1:?usage: db-backup.sh <app>}
K="kubectl --kubeconfig ${HOMELAB_KUBECONFIG:-$HOME/.kube/homelab} --context homelab -n cnpg-prod"
CLUSTER=$($K get clusters.postgresql.cnpg.io -o name | sed 's|.*/||' | grep "^$APP-db-" | head -1)
[ -n "$CLUSTER" ] || { echo "no CNPG cluster $APP-db-* in cnpg-prod" >&2; exit 1; }
NAME="$CLUSTER-manual-$(date +%Y%m%d-%H%M%S)"
$K create -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $NAME
spec:
  cluster:
    name: $CLUSTER
  method: barmanObjectStore
YAML
for _ in $(seq 1 60); do
  phase=$($K get backup "$NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case $phase in
    completed) echo "backup $NAME completed"; exit 0 ;;
    failed) echo "backup $NAME failed: $($K get backup "$NAME" -o jsonpath='{.status.error}')" >&2; exit 1 ;;
  esac
  sleep 10
done
echo "backup $NAME not completed after 10 minutes (phase: ${phase:-none})" >&2; exit 1
