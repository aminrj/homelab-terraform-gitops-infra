#!/bin/bash

# Test scenarios for LLM Gateway
LLM_URL="http://llm-gateway.local"

echo "🧪 Testing LLM Gateway..."

# Test 1: Brute Force Detection
echo "Test 1: Brute Force Attack"
curl -s -X POST "$LLM_URL/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "CRITICAL: 100 failed login attempts from 203.0.113.45 in 2 minutes",
    "task_type": "security_analysis"
  }' | jq '.response' | head -3

# Test 2: Code Review
echo -e "\nTest 2: Code Security Review"
curl -s -X POST "$LLM_URL/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "import os; os.system(request.args.get(\"cmd\"))",
    "task_type": "code_analysis"
  }' | jq '.response' | head -3

# Test 3: Performance Check
echo -e "\nTest 3: Performance Metrics"
curl -s -X POST "$LLM_URL/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Quick test",
    "task_type": "general"
  }' | jq '.usage'

echo -e "\n✅ Tests completed"
