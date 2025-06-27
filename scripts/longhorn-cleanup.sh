#!/bin/bash
# Brute force PVC deletion

STUCK_PVCS="commafeed-db-cnpg-v1-1:cnpg-prod linkding-db-cnpg-v1-1:cnpg-prod listmonk-db-cnpg-v1-1:cnpg-prod listmonk-db-cnpg-v1-2:cnpg-prod n8n-db-cnpg-v1-1:cnpg-prod n8n-db-cnpg-v1-2:cnpg-prod n8n-db-cnpg-v1-2:cnpg-qa alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0:monitoring alertmanager-kube-promethues-stack-kube-alertmanager-db-alertmanager-kube-promethues-stack-kube-alertmanager-0:monitoring kube-promethues-stack-grafana:monitoring prometheus-kube-promethues-stack-kube-prometheus-db-prometheus-kube-promethues-stack-kube-prometheus-0:monitoring n8n-data:n8n-prod n8n-data:n8n-qa ollama-model-cache:ollama"

for pvc_info in $STUCK_PVCS; do
  pvc=$(echo $pvc_info | cut -d: -f1)
  namespace=$(echo $pvc_info | cut -d: -f2)

  echo "=== Brute forcing $namespace/$pvc ==="

  # Method 1: Multiple patch attempts
  kubectl patch pvc "$pvc" -n "$namespace" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
  kubectl patch pvc "$pvc" -n "$namespace" --type='merge' -p='{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  kubectl patch pvc "$pvc" -n "$namespace" --type='merge' -p='{"metadata":{"finalizers":null}}' 2>/dev/null || true

  # Method 2: Replace with cleaned version
  kubectl get pvc "$pvc" -n "$namespace" -o json |
    jq 'del(.metadata.finalizers) | del(.metadata.deletionTimestamp) | del(.metadata.deletionGracePeriodSeconds) | .metadata.finalizers = []' |
    kubectl replace --force -f - 2>/dev/null || true

  # Method 3: Force delete
  kubectl delete pvc "$pvc" -n "$namespace" --force --grace-period=0 2>/dev/null || true

  sleep 1
done
