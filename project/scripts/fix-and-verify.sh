#!/bin/bash

# Simple script to fix everything and get it working

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Fixing DeathStarBench Deployment ==="
echo ""

# Step 1: Create Lua script ConfigMaps
echo "Step 1: Creating Lua script ConfigMaps..."
if [ -f "${PROJECT_ROOT}/scripts/create-lua-configmap-solution.sh" ]; then
    "${PROJECT_ROOT}/scripts/create-lua-configmap-solution.sh"
else
    echo "  ⚠ Script not found, skipping..."
fi
echo ""

# Step 2: Verify ConfigMaps exist
echo "Step 2: Verifying ConfigMaps..."
REQUIRED_CMAPS=(
  "nginx-lua-scripts-wrk2-api-user"
  "nginx-lua-scripts-api-user"
)

MISSING=0
for cm in "${REQUIRED_CMAPS[@]}"; do
    if kubectl get configmap "$cm" &>/dev/null; then
        echo "  ✓ $cm exists"
    else
        echo "  ✗ $cm MISSING"
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "ERROR: Required ConfigMaps are missing!"
    echo "Please run: ./scripts/create-lua-configmap-solution.sh"
    exit 1
fi
echo ""

# Step 3: Ensure nginx-thrift service exists
echo "Step 3: Ensuring nginx-thrift service exists..."
if ! kubectl get service nginx-thrift &>/dev/null; then
    echo "  Creating nginx-thrift service..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/services/nginx-thrift.yaml"
    echo "  ✓ Service created"
else
    echo "  ✓ Service already exists"
fi
echo ""

# Step 4: Restart nginx-thrift to pick up ConfigMaps
echo "Step 4: Restarting nginx-thrift deployment..."
kubectl rollout restart deployment/nginx-thrift-deployment
echo "  Waiting for rollout..."
kubectl rollout status deployment/nginx-thrift-deployment --timeout=60s
echo "  ✓ Deployment restarted"
echo ""

# Step 5: Verify pod is running
echo "Step 5: Verifying nginx-thrift pod..."
sleep 5
NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$NGINX_POD" ]; then
    echo "  ✗ No running nginx-thrift pod found"
    echo "  Checking pod status..."
    kubectl get pods -l app=nginx-thrift
    exit 1
else
    echo "  ✓ Pod running: $NGINX_POD"
fi
echo ""

# Step 6: Verify Lua scripts are mounted
echo "Step 6: Verifying Lua scripts are mounted..."
if kubectl exec "$NGINX_POD" -- test -f /usr/local/openresty/nginx/lua-scripts/wrk2-api/user/register.lua 2>/dev/null; then
    echo "  ✓ register.lua is mounted"
else
    echo "  ✗ register.lua is NOT mounted!"
    echo "  This means the ConfigMap mounting isn't working."
    exit 1
fi
echo ""

# Step 7: Check if port-forward is needed
echo "Step 7: Checking port-forward..."
if lsof -ti:8080 &>/dev/null; then
    echo "  ✓ Port-forward is running"
else
    echo "  ⚠ Port-forward is NOT running"
    echo "  Start it with: kubectl port-forward svc/nginx-thrift 8080:8080"
    echo "  (Run this in a separate terminal)"
fi
echo ""

# Step 8: Test endpoint
echo "Step 8: Testing endpoint..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>&1 | grep -q "200\|404\|403"; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>&1)
    echo "  ✓ nginx-thrift responds (HTTP $HTTP_CODE)"
    
    echo ""
    echo "=== Testing /wrk2-api/user/register endpoint ==="
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST http://localhost:8080/wrk2-api/user/register \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      -d 'user_id=99999&username=testuser&first_name=Test&last_name=User&password=test123' 2>&1)
    
    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | grep -v "HTTP_STATUS" | head -3)
    
    echo "Response Status: $HTTP_STATUS"
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "  ✓ SUCCESS! Endpoint is working!"
    else
        echo "  Response Body:"
        echo "$BODY"
        echo ""
        echo "  ⚠ Endpoint returned $HTTP_STATUS - check nginx-thrift logs:"
        echo "    kubectl logs $NGINX_POD --tail=20"
    fi
else
    echo "  ✗ nginx-thrift not responding"
    echo "  Make sure port-forward is running: kubectl port-forward svc/nginx-thrift 8080:8080"
fi

echo ""
echo "=== Done ==="

