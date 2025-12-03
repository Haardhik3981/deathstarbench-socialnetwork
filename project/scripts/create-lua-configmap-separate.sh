#!/bin/bash

# Create ConfigMaps for nginx Lua scripts
# Since ConfigMap keys can't contain slashes, we create separate ConfigMaps
# for each subdirectory and mount them at the appropriate paths
# This matches the OpenShift deployment approach

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMaps (Separate per subdirectory) ==="
echo ""

# Verify source directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "ERROR: Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

# Delete old ConfigMaps
echo "Deleting existing ConfigMaps (if any)..."
kubectl delete configmap nginx-lua-scripts-api 2>/dev/null && echo "  ✓ Deleted nginx-lua-scripts-api" || true
kubectl delete configmap nginx-lua-scripts-wrk2-api 2>/dev/null && echo "  ✓ Deleted nginx-lua-scripts-wrk2-api" || true
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "  ✓ Deleted nginx-lua-scripts" || true

cd "${LUA_SCRIPTS_DIR}"

# Create ConfigMap for api/ subdirectory
if [ -d "api" ]; then
    echo ""
    echo "Creating ConfigMap for api/ subdirectory..."
    kubectl create configmap nginx-lua-scripts-api --from-file=api/
    echo "✓ Created nginx-lua-scripts-api"
fi

# Create ConfigMap for wrk2-api/ subdirectory  
if [ -d "wrk2-api" ]; then
    echo ""
    echo "Creating ConfigMap for wrk2-api/ subdirectory..."
    kubectl create configmap nginx-lua-scripts-wrk2-api --from-file=wrk2-api/
    echo "✓ Created nginx-lua-scripts-wrk2-api"
fi

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMaps..."
sleep 1

API_COUNT=$(kubectl get configmap nginx-lua-scripts-api -o json 2>/dev/null | grep -c '":' || echo "0")
WRK2_COUNT=$(kubectl get configmap nginx-lua-scripts-wrk2-api -o json 2>/dev/null | grep -c '":' || echo "0")

if [ "$API_COUNT" -gt 0 ] && [ "$WRK2_COUNT" -gt 0 ]; then
    echo "✓ SUCCESS! Both ConfigMaps created"
    echo "  - nginx-lua-scripts-api: ~$API_COUNT files"
    echo "  - nginx-lua-scripts-wrk2-api: ~$WRK2_COUNT files"
    echo ""
    echo "⚠ IMPORTANT: The deployment needs to be updated to mount these separately!"
    echo ""
    echo "The deployment currently expects a single ConfigMap 'nginx-lua-scripts'"
    echo "mounted at /usr/local/openresty/nginx/lua-scripts"
    echo ""
    echo "You need to update the deployment to mount:"
    echo "  - nginx-lua-scripts-api at /usr/local/openresty/nginx/lua-scripts/api"
    echo "  - nginx-lua-scripts-wrk2-api at /usr/local/openresty/nginx/lua-scripts/wrk2-api"
    echo ""
    echo "OR, we can create a single ConfigMap with flattened keys (using underscores)."
    echo "Would you like me to create a script that updates the deployment?"
else
    echo "⚠ Some ConfigMaps may be empty"
    echo "  API ConfigMap keys: $API_COUNT"
    echo "  WRK2-API ConfigMap keys: $WRK2_COUNT"
fi

