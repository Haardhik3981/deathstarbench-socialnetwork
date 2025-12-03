#!/bin/bash

# Apply the final Lua ConfigMap fix with all 8 ConfigMaps

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOYMENT_FILE="${PROJECT_ROOT}/kubernetes/deployments/nginx-thrift-deployment.yaml"

echo "=== Applying Final Lua ConfigMap Fix ==="
echo ""

# Step 1: Verify all 8 ConfigMaps exist
echo "Step 1: Verifying all ConfigMaps exist..."
REQUIRED_CM=(
    "nginx-lua-scripts-api-home-timeline"
    "nginx-lua-scripts-api-post"
    "nginx-lua-scripts-api-user"
    "nginx-lua-scripts-api-user-timeline"
    "nginx-lua-scripts-wrk2-api-home-timeline"
    "nginx-lua-scripts-wrk2-api-post"
    "nginx-lua-scripts-wrk2-api-user"
    "nginx-lua-scripts-wrk2-api-user-timeline"
)

MISSING=0
for cm in "${REQUIRED_CM[@]}"; do
    if kubectl get configmap "$cm" >/dev/null 2>&1; then
        DATA_COUNT=$(kubectl get configmap "$cm" -o jsonpath='{.data}' 2>/dev/null | grep -o '":' | wc -l | tr -d ' ' || echo "0")
        if [ "$DATA_COUNT" -gt 0 ]; then
            echo "  ✓ $cm ($DATA_COUNT files)"
        else
            echo "  ✗ $cm (empty!)"
            MISSING=$((MISSING + 1))
        fi
    else
        echo "  ✗ $cm (not found!)"
        MISSING=$((MISSING + 1))
    fi
done

if [ "$MISSING" -gt 0 ]; then
    echo ""
    echo "ERROR: $MISSING ConfigMaps are missing or empty!"
    echo "Please run: ./scripts/create-lua-configmap-solution.sh"
    exit 1
fi

echo ""
echo "✓ All 8 ConfigMaps exist and have data"

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
echo "Step 5: Verifying files are mounted..."
POD_NAME=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    echo "⚠ No pod found yet, may still be starting"
else
    echo "Checking pod: $POD_NAME"
    echo ""
    echo "Checking critical file: wrk2-api/user/register.lua"
    if kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/user/register.lua 2>&1; then
        echo ""
        echo "✓ SUCCESS! File is mounted correctly!"
        echo ""
        echo "Checking a few more files..."
        kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/api/user/register.lua 2>&1 && echo "  ✓ api/user/register.lua" || echo "  ✗ api/user/register.lua"
        kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/post/compose.lua 2>&1 && echo "  ✓ wrk2-api/post/compose.lua" || echo "  ✗ wrk2-api/post/compose.lua"
    else
        echo ""
        echo "✗ ERROR: File not found"
        echo ""
        echo "Checking directory structure:"
        kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/ 2>&1 || true
    fi
fi

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Test the endpoint:"
echo "   ./k6-tests/test-endpoint.sh"
echo ""
echo "2. If it works (returns 200), run your k6 test:"
echo "   BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh constant-load"
echo ""
echo "3. Check pod logs if there are still errors:"
echo "   kubectl logs -l app=nginx-thrift --tail=50"

