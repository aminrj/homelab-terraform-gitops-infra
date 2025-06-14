#!/bin/bash

echo "🚀 Deploying Enhanced LLM Testing Infrastructure"
echo "================================================"

# Step 1: Deploy multiple model instances
echo "📦 Step 1: Deploying multiple Ollama model instances..."
kubectl apply -f - <<EOF
$(cat llm_model_manager.yaml)
EOF

echo "⏳ Waiting for model instances to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/ollama-small-models -n llm-models
kubectl wait --for=condition=available --timeout=300s deployment/ollama-medium-models -n llm-models

# Step 2: Update LLM Gateway with enhanced version
echo "🔄 Step 2: Updating LLM Gateway with enhanced routing..."
kubectl apply -f - <<EOF
$(grep -A 1000 "Enhanced LLM Gateway with Model Router" llm_model_manager.yaml)
EOF

# Step 3: Deploy test runner
echo "🧪 Step 3: Deploying automated test runner..."
kubectl apply -f - <<EOF
$(cat automated_testing_system.yaml)
EOF

echo "⏳ Waiting for test runner to be ready..."
kubectl wait --for=condition=available --timeout=180s deployment/llm-test-runner -n llm-testing

# Step 4: Update n8n with enhanced nodes
echo "📝 Step 4: Adding enhanced n8n nodes..."
kubectl apply -f - <<EOF
$(grep -A 200 "Enhanced n8n ConfigMap" automated_testing_system.yaml)
EOF

# Restart n8n to pick up new nodes
kubectl rollout restart deployment/n8n -n n8n

# Step 5: Set up ingress hosts in /etc/hosts (for local development)
echo "🌐 Step 5: Setting up local DNS entries..."
CLUSTER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "Adding entries to /etc/hosts..."
sudo bash -c "cat >> /etc/hosts << EOF
$CLUSTER_IP llm-test.local
$CLUSTER_IP llm-tests.local
EOF"

# Step 6: Verify everything is working
echo "✅ Step 6: Verification and testing..."

echo "Checking model deployments..."
kubectl get pods -n llm-models
kubectl get pods -n llm-gateway  
kubectl get pods -n llm-testing

echo "Testing connectivity..."
echo "🔍 Testing small models..."
kubectl exec -it deployment/ollama-small-models -n llm-models -- ollama list

echo "🔍 Testing medium models..."
kubectl exec -it deployment/ollama-medium-models -n llm-models -- ollama list

echo "🔍 Testing LLM Gateway..."
kubectl port-forward -n llm-gateway svc/llm-gateway-enhanced-service 8080:80 &
GATEWAY_PID=$!
sleep 3

curl -s http://localhost:8080/models | jq .
curl -X POST http://localhost:8080/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Test quick response","task_type":"quick_test","auto_select_model":true}' | jq .

kill $GATEWAY_PID 2>/dev/null

echo "🔍 Testing automated test runner..."
kubectl port-forward -n llm-testing svc/llm-test-runner-service 8081:80 &
TESTER_PID=$!
sleep 3

curl -s http://localhost:8081/test/suites | jq .

kill $TESTER_PID 2>/dev/null

echo ""
echo "🎉 Deployment Complete!"
echo "======================="
echo ""
echo "🌐 Access your services:"
echo "   • LLM Testing Dashboard: http://llm-test.local"
echo "   • Test Runner Dashboard: http://llm-tests.local"
echo "   • n8n Workflows: http://n8n.local (if configured)"
echo ""
echo "🧪 Available Models:"
echo "   Small (Fast):   phi3:mini, qwen2.5:1.5b, tinyllama"
echo "   Medium (Balanced): llama3.2:3b, mistral:7b, qwen2.5:7b"  
echo "   Large (Quality): llama3:latest"
echo ""
echo "🚀 Quick Testing Commands:"
echo "   kubectl port-forward -n llm-gateway svc/llm-gateway-enhanced-service 8080:80"
echo "   curl http://localhost:8080"
echo ""
echo "   kubectl port-forward -n llm-testing svc/llm-test-runner-service 8081:80"
echo "   curl http://localhost:8081"
echo ""
echo "📋 n8n Custom Nodes Added:"
echo "   • LLM Test Runner - Run automated test suites"
echo "   • LLM Model Manager - Manage and compare models"
echo "   • Enhanced LLM Gateway - Route to different model sizes"
echo ""

# Create a simple test script
cat > test_llm_setup.sh << 'SCRIPT'
#!/bin/bash
echo "🧪 Quick LLM Setup Test"
echo "======================"

# Test different model sizes
echo "Testing small model (phi3:mini)..."
curl -s -X POST http://llm-test.local/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello","model":"phi3:mini"}' | jq -r '.response'

echo -e "\nTesting medium model (llama3.2:3b)..."  
curl -s -X POST http://llm-test.local/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"What is cybersecurity?","model":"llama3.2:3b"}' | jq -r '.response'

echo -e "\nTesting auto model selection..."
curl -s -X POST http://llm-test.local/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Analyze this security alert: Multiple failed logins","task_type":"security_analysis","auto_select_model":true}' | jq -r '.model + ": " + .response'

echo -e "\nRunning automated security tests..."
curl -s http://llm-tests.local/test/suite \
  -H "Content-Type: application/json" \
  -d '{"suite_name":"security_tests"}' | jq '.summary'

echo -e "\n✅ Setup test complete!"
SCRIPT

chmod +x test_llm_setup.sh

echo "📄 Created test_llm_setup.sh - run this to test your setup"
echo ""
echo "🎯 Next Steps:"
echo "1. Wait for all models to download (check with: kubectl logs -f deployment/ollama-small-models -n llm-models)"
echo "2. Test the setup: ./test_llm_setup.sh"
echo "3. Open http://llm-test.local in your browser"
echo "4. Create n8n workflows using the new LLM nodes"
echo ""
echo "💡 Tips:"
echo "• Use phi3:mini for quick iteration and testing"
echo "• Use mistral:7b or llama3.2:3b for balanced performance"
echo "• Use llama3 for highest quality responses"
echo "• The system auto-selects models based on task type and message length"
echo ""

# Create a monitoring script
cat > monitor_llm_performance.sh << 'SCRIPT'
#!/bin/bash
echo "📊 LLM Performance Monitor"
echo "========================="

while true; do
    clear
    echo "📊 LLM Performance Monitor - $(date)"
    echo "========================="
    
    # Check pod status
    echo "🔍 Pod Status:"
    kubectl get pods -n llm-models -o wide
    kubectl get pods -n llm-gateway -o wide
    kubectl get pods -n llm-testing -o wide
    
    echo -e "\n💾 Resource Usage:"
    kubectl top pods -n llm-models 2>/dev/null || echo "Metrics not available"
    
    echo -e "\n🚀 Quick Performance Test:"
    start_time=$(date +%s%3N)
    response=$(curl -s -X POST http://llm-test.local/chat \
        -H "Content-Type: application/json" \
        -d '{"message":"Hello","model":"phi3:mini"}' 2>/dev/null)
    end_time=$(date +%s%3N)
    
    if [ $? -eq 0 ]; then
        response_time=$((end_time - start_time))
        echo "✅ Phi3:mini response time: ${response_time}ms"
        echo "📝 Response: $(echo $response | jq -r '.response' | cut -c1-50)..."
    else
        echo "❌ Gateway not responding"
    fi
    
    echo -e "\n🧪 Latest Test Results:"
    curl -s http://llm-tests.local/test/suites 2>/dev/null | jq -r '.suites[]' || echo "Test runner not available"
    
    echo -e "\nPress Ctrl+C to exit, refreshing in 30 seconds..."
    sleep 30
done
SCRIPT

chmod +x monitor_llm_performance.sh

echo "📊 Created monitor_llm_performance.sh - run this to monitor your LLM infrastructure"

# Create n8n workflow examples
cat > example_n8n_workflows.json << 'JSON'
{
  "workflows": [
    {
      "name": "Security Alert Analysis Pipeline",
      "description": "Processes security alerts through multiple LLM models",
      "nodes": [
        {
          "type": "webhook",
          "name": "Security Alert Webhook",
          "webhook_path": "/security-alert"
        },
        {
          "type": "llmGateway", 
          "name": "Quick Triage",
          "model": "phi3:mini",
          "task_type": "security_analysis"
        },
        {
          "type": "if",
          "name": "Check Risk Level",
          "condition": "{{$json.llm_response}} includes 'HIGH'"
        },
        {
          "type": "llmGateway",
          "name": "Detailed Analysis", 
          "model": "mistral:7b",
          "task_type": "security_analysis"
        },
        {
          "type": "llmTestRunner",
          "name": "Validate Response",
          "test_action": "single_test"
        }
      ]
    },
    {
      "name": "Code Review Automation",
      "description": "Automated security code review workflow",
      "nodes": [
        {
          "type": "webhook",
          "name": "Code Review Trigger"
        },
        {
          "type": "llmGateway",
          "name": "Security Code Review",
          "model": "qwen2.5:7b", 
          "task_type": "code_analysis"
        },
        {
          "type": "llmModelManager",
          "name": "Compare Models",
          "action": "compare_models"
        }
      ]
    },
    {
      "name": "LLM Performance Testing",
      "description": "Continuous testing of LLM model performance",
      "nodes": [
        {
          "type": "cron",
          "name": "Hourly Test Schedule",
          "schedule": "0 * * * *"
        },
        {
          "type": "llmTestRunner",
          "name": "Run All Tests",
          "test_action": "run_all"
        },
        {
          "type": "if",
          "name": "Check Success Rate",
          "condition": "{{$json.test_results.summary.success_rate}} < 80"
        },
        {
          "type": "webhook",
          "name": "Alert on Failure"
        }
      ]
    }
  ]
}
JSON

echo "📋 Created example_n8n_workflows.json - import these into n8n for ready-made workflows"

# Create a troubleshooting guide
cat > troubleshooting.md << 'MD'
# 🔧 LLM Infrastructure Troubleshooting Guide

## Common Issues and Solutions

### 1. Models Not Loading
**Problem**: Ollama pods are running but models aren't available
**Solution**:
```bash
# Check model download progress
kubectl logs -f deployment/ollama-small-models -n llm-models
kubectl logs -f deployment/ollama-medium-models -n llm-models

# Manually pull models if needed
kubectl exec -it deployment/ollama-small-models -n llm-models -- ollama pull phi3:mini
```

### 2. Gateway Connection Issues
**Problem**: LLM Gateway can't reach Ollama services
**Solution**:
```bash
# Test internal connectivity
kubectl exec -it deployment/llm-gateway-enhanced -n llm-gateway -- curl http://ollama-small-service.llm-models.svc.cluster.local:11434/api/tags

# Check service endpoints
kubectl get endpoints -n llm-models
```

### 3. Slow Response Times
**Problem**: Models taking too long to respond
**Solutions**:
- Use smaller models for testing (phi3:mini, tinyllama)
- Check resource allocation: `kubectl top pods -n llm-models`
- Verify CPU affinity and node selection

### 4. Test Runner Failures
**Problem**: Automated tests failing
**Solution**:
```bash
# Check test runner logs
kubectl logs deployment/llm-test-runner -n llm-testing

# Test connectivity to gateway
kubectl exec -it deployment/llm-test-runner -n llm-testing -- curl http://llm-gateway-enhanced-service.llm-gateway.svc.cluster.local/health
```

### 5. n8n Node Issues
**Problem**: Custom LLM nodes not appearing in n8n
**Solution**:
```bash
# Restart n8n to load new nodes
kubectl rollout restart deployment/n8n -n n8n

# Check if ConfigMap was applied
kubectl get configmap n8n-enhanced-llm -n n8n -o yaml
```

## Performance Optimization

### Model Selection Strategy
- **Quick Testing**: phi3:mini (fastest, 1.8B params)
- **Development**: llama3.2:3b (balanced, good quality)
- **Production**: mistral:7b or llama3 (best quality)

### Resource Allocation
```yaml
# Recommended resource limits
small_models:  cpu: 2-4,  memory: 4-8Gi
medium_models: cpu: 4-6,  memory: 12-16Gi  
large_models:  cpu: 6-10, memory: 24-28Gi
```

### Monitoring Commands
```bash
# Overall system status
kubectl get pods --all-namespaces | grep llm

# Resource usage
kubectl top pods -n llm-models
kubectl top nodes

# Model availability
curl http://llm-test.local/models

# Test performance
curl -X POST http://llm-test.local/chat -H "Content-Type: application/json" -d '{"message":"test","model":"phi3:mini"}'
```
MD

echo "📖 Created troubleshooting.md - comprehensive troubleshooting guide"

echo ""
echo "🎯 Summary of what was created:"
echo "==============================="
echo "✅ Multi-model Ollama deployments (small, medium, large)"
echo "✅ Enhanced LLM Gateway with intelligent model routing"
echo "✅ Automated test runner with comprehensive test suites"
echo "✅ Enhanced n8n nodes for LLM testing and management"
echo "✅ Web dashboards for testing and monitoring"
echo "✅ Internal cluster networking (no port-forwarding needed)"
echo "✅ Performance monitoring and troubleshooting tools"
echo ""
echo "🚀 You now have a robust, scalable LLM testing infrastructure!"
echo "   Perfect for developing and testing AI agents and n8n workflows."