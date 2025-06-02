#!/bin/bash

set -euo pipefail

NAMESPACE="longhorn-system"

echo "⏳ Patching deleting-confirmation-flag to true..."
kubectl patch settings.longhorn.io deleting-confirmation-flag \
  -n ${NAMESPACE} \
  --type=merge \
  -p '{"value": "true"}'

echo "✅ Flag patched."

echo "🔁 Recreating longhorn-uninstall Job if it exists..."
kubectl delete job longhorn-uninstall -n ${NAMESPACE} --ignore-not-found

echo "🚀 Creating new longhorn-uninstall Job..."
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: longhorn-uninstall
  namespace: ${NAMESPACE}
spec:
  template:
    spec:
      serviceAccountName: longhorn-service-account
      containers:
      - name: longhorn-uninstall
        image: longhornio/uninstaller:v1.8.1
        imagePullPolicy: Always
        command: ["/bin/sh"]
        args:
          - -c
          - longhorn-uninstall
      restartPolicy: Never
  backoffLimit: 1
EOF

echo "📡 Waiting for job completion..."
kubectl wait --for=condition=complete job/longhorn-uninstall -n ${NAMESPACE} --timeout=120s || {
  echo "❌ Uninstall job failed or timed out. Check logs:"
  kubectl logs job/longhorn-uninstall -n ${NAMESPACE}
  exit 1
}

echo "🧼 Deleting Longhorn namespace..."
kubectl delete ns ${NAMESPACE}

echo "✅ Longhorn successfully uninstalled."
