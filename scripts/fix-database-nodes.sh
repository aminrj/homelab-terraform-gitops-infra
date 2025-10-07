#!/bin/bash
set -e

# Fix database pods stuck on unavailable nodes
# This script deletes and recreates database clusters that are stuck on unavailable nodes

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/microk8s-config}"

echo "=== Fixing Database Node Affinity Issues ==="
echo ""

# List of databases that need to be fixed (stuck on microk8s-prod-llm-pve2-1)
DATABASES=(
    "linkding-db-cnpg-v1"
    "wallabag-db-cnpg-v1"
    "n8n-db-cnpg-v3"
    "listmonk-db-cnpg-v1"
)

for db in "${DATABASES[@]}"; do
    echo "Processing $db..."

    # Check if cluster exists and has pending pods
    if kubectl --kubeconfig="$KUBECONFIG" get cluster "$db" -n cnpg-prod &>/dev/null; then
        echo "  Deleting cluster $db..."
        kubectl --kubeconfig="$KUBECONFIG" delete cluster "$db" -n cnpg-prod --timeout=60s || true

        echo "  Waiting for PVCs to be deleted..."
        sleep 10

        echo "✓ $db cleaned up"
    else
        echo "  $db not found, skipping"
    fi
    echo ""
done

echo "=== Database cleanup complete ==="
echo ""
echo "Next steps:"
echo "1. Redeploy databases using: cd environments/prod && terraform apply"
echo "2. Or use ArgoCD to sync the database applications"
echo ""
