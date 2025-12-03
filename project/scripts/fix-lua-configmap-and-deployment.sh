#!/bin/bash

# Complete solution: Create ConfigMaps for subdirectories and update deployment
# This matches the OpenShift approach which works reliably

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"
DEPLOYMENT_FILE="${PROJECT_ROOT}/kubernetes/deployments/nginx-thrift-deployment.yaml"

echo "=== Complete Fix: ConfigMaps + Deployment Update ==="
echo ""

# Step 1: Create ConfigMaps for each subdirectory
echo "Step 1: Creating ConfigMaps for subdirectories..."
cd "${LUA_SCRIPTS_DIR}"

# Delete old
kubectl delete configmap nginx-lua-scripts-api 2>/dev/null || true
kubectl delete configmap nginx-lua-scripts-wrk2-api 2>/dev/null || true
kubectl delete configmap nginx-lua-scripts 2>/dev/null || true

# Create for api/
if [ -d "api" ] && [ "$(find api -type f | wc -l)" -gt 0 ]; then
    echo "  Creating nginx-lua-scripts-api..."
    kubectl create configmap nginx-lua-scripts-api --from-file=api/
    echo "  ✓ Created"
fi

# Create for wrk2-api/
if [ -d "wrk2-api" ] && [ "$(find wrk2-api -type f | wc -l)" -gt 0 ]; then
    echo "  Creating nginx-lua-scripts-wrk2-api..."
    kubectl create configmap nginx-lua-scripts-wrk2-api --from-file=wrk2-api/
    echo "  ✓ Created"
fi

cd "${PROJECT_ROOT}"

# Step 2: Update deployment to mount subdirectories separately
echo ""
echo "Step 2: Updating deployment to mount subdirectories..."
echo "  Backup: ${DEPLOYMENT_FILE}.backup"

# Backup
cp "${DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}.backup"

# Check if already updated
if grep -q "nginx-lua-scripts-api" "${DEPLOYMENT_FILE}"; then
    echo "  Deployment already updated, skipping..."
else
    echo "  Updating volumeMounts and volumes sections..."
    
    # This is complex - we'd need to use sed or a proper YAML tool
    # For now, let's create a patch file
    cat > /tmp/deployment-patch.yaml <<'EOFPATCH'
      # Lua scripts - API subdirectory
      - name: lua-scripts-api
        mountPath: /usr/local/openresty/nginx/lua-scripts/api
        readOnly: true
      # Lua scripts - WRK2-API subdirectory  
      - name: lua-scripts-wrk2-api
        mountPath: /usr/local/openresty/nginx/lua-scripts/wrk2-api
        readOnly: true
EOFPATCH
    
    echo "  Manual update required - see instructions below"
fi

echo ""
echo "Step 3: Summary"
echo ""
echo "ConfigMaps created:"
kubectl get configmap | grep nginx-lua-scripts || echo "  (none found)"
echo ""
echo "⚠ ACTION REQUIRED:"
echo "  1. Update the deployment YAML to:"
echo "     - Remove the single 'lua-scripts' volumeMount"
echo "     - Add two volumeMounts:"
echo "       * nginx-lua-scripts-api at /usr/local/openresty/nginx/lua-scripts/api"
echo "       * nginx-lua-scripts-wrk2-api at /usr/local/openresty/nginx/lua-scripts/wrk2-api"
echo "     - Update volumes section similarly"
echo ""
echo "  2. Apply the updated deployment:"
echo "     kubectl apply -f ${DEPLOYMENT_FILE}"
echo ""
echo "  3. Restart the deployment:"
echo "     kubectl rollout restart deployment/nginx-thrift-deployment"

