#!/bin/bash
set -e

# Recreate database clusters stuck on unavailable nodes
# Uses kustomize to delete and recreate databases declaratively

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/microk8s-config}"

echo "=== Recreating Database Clusters ==="
echo ""

# Databases to recreate
DATABASES=("linkding" "n8n" "wallabag")

for db in "${DATABASES[@]}"; do
    echo "=== Processing $db database ==="

    DB_PATH="$PROJECT_ROOT/databases/$db/overlays/prod"

    if [ ! -d "$DB_PATH" ]; then
        echo "  ERROR: $DB_PATH not found"
        continue
    fi

    echo "  Deleting existing cluster..."
    kubectl --kubeconfig="$KUBECONFIG" delete -k "$DB_PATH" --timeout=60s || echo "  (cluster may not exist)"

    echo "  Waiting for resources to be deleted..."
    sleep 5

    echo "  Creating new cluster..."
    kubectl --kubeconfig="$KUBECONFIG" apply -k "$DB_PATH"

    echo "✓ $db cluster recreated"
    echo ""
done

echo "=== Checking cluster status ==="
kubectl --kubeconfig="$KUBECONFIG" get clusters -n cnpg-prod

echo ""
echo "=== Next Steps ==="
echo "Monitor the clusters with:"
echo "  watch kubectl --kubeconfig=$KUBECONFIG get clusters -n cnpg-prod"
echo "  watch kubectl --kubeconfig=$KUBECONFIG get pods -n cnpg-prod"
echo ""
