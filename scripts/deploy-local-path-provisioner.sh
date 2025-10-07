#!/bin/bash
set -e

# Deploy local-path provisioner from Rancher
# This is the same provisioner used by MicroK8s

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/microk8s-config}"

echo "=== Deploying local-path provisioner ==="

kubectl --kubeconfig="$KUBECONFIG" apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml

echo "Waiting for provisioner to be ready..."
sleep 10

kubectl --kubeconfig="$KUBECONFIG" get pods -n local-path-storage
kubectl --kubeconfig="$KUBECONFIG" get storageclass local-path

echo "✓ Local-path provisioner deployed"
