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
