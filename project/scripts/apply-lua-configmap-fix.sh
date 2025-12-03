#!/bin/bash

# Apply the Lua ConfigMap fix: Update deployment and verify

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOYMENT_FILE="${PROJECT_ROOT}/kubernetes/deployments/nginx-thrift-deployment.yaml"

echo "=== Applying Lua ConfigMap Fix ==="
echo ""

# Step 1: Verify ConfigMaps exist
echo "Step 1: Verifying ConfigMaps..."
if kubectl get configmap nginx-lua-scripts-api >/dev/null 2>&1 && \
   kubectl get configmap nginx-lua-scripts-wrk2-api >/dev/null 2>&1; then
    echo "✓ Both ConfigMaps exist"
    kubectl get configmap nginx-lua-scripts-api nginx-lua-scripts-wrk2-api
else
    echo "✗ ERROR: ConfigMaps not found!"
    echo "Please run: ./scripts/create-lua-configmap-separate.sh"
    exit 1
fi

# Step 2: Apply updated deployment
echo ""
echo "Step 2: Applying updated deployment..."
if kubectl apply -f "${DEPLOYMENT_FILE}" 2>&1; then
    echo "✓ Deployment updated"
else
    echo "✗ ERROR: Failed to apply deployment"
    exit 1
fi

# Step 3: Restart deployment
echo ""
echo "Step 3: Restarting deployment..."
kubectl rollout restart deployment/nginx-thrift-deployment
echo "✓ Restart initiated"

# Step 4: Wait for rollout
echo ""
echo "Step 4: Waiting for rollout to complete..."
if kubectl rollout status deployment/nginx-thrift-deployment --timeout=120s 2>&1; then
    echo "✓ Deployment is ready"
else
    echo "⚠ Deployment may still be rolling out"
    echo "Check status with: kubectl get pods -l app=nginx-thrift"
fi

# Step 5: Verify files are mounted
echo ""
echo "Step 5: Verifying files are mounted in pod..."
POD_NAME=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    echo "⚠ No pod found yet, may still be starting"
    echo "Wait a moment and check: kubectl get pods -l app=nginx-thrift"
else
    echo "Checking pod: $POD_NAME"
    echo ""
    echo "Checking if wrk2-api/user/register.lua exists:"
    if kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/user/register.lua 2>&1; then
        echo ""
        echo "✓ SUCCESS! File is mounted correctly!"
    else
        echo ""
        echo "✗ ERROR: File not found at expected location"
        echo ""
        echo "Checking what's actually mounted:"
        kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/ 2>&1 || true
        echo ""
        kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/ 2>&1 || true
    fi
fi

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Test the endpoint:"
echo "   ./k6-tests/test-endpoint.sh"
echo ""
echo "2. If it works, run your k6 test:"
echo "   BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh constant-load"
echo ""
echo "3. Check pod logs if there are still errors:"
echo "   kubectl logs -l app=nginx-thrift --tail=50"

