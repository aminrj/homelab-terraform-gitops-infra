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
