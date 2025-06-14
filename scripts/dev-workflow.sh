#!/bin/bash

echo "🚀 LLM Development Environment Setup"

# 1. Update gateway
echo "Updating LLM Gateway..."
kubectl apply -k apps/llm-gateway/base/

# 2. Wait for rollout
echo "Waiting for deployment..."
kubectl rollout status deployment/llm-gateway -n llm-gateway

# 3. Setup port forwards
echo "Setting up access..."
kubectl port-forward -n llm-gateway svc/llm-gateway-service 8080:80 &
kubectl port-forward -n n8n-qa svc/n8n 5678:80 &

echo "✅ Ready!"
echo "🌐 LLM Gateway UI: http://localhost:8080"
echo "🔧 n8n Interface: http://localhost:5678"
echo "🧪 Run tests: ./test-llm-gateway.sh"

# Keep port forwards alive
wait
