#!/bin/bash

# Create ConfigMap by creating separate ConfigMaps for each subdirectory
# Then we'll need to update the deployment to mount them separately

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMaps (one per subdirectory) ==="
echo ""

cd "${LUA_SCRIPTS_DIR}"

# Delete old single ConfigMap
kubectl delete configmap nginx-lua-scripts 2>/dev/null || true

# Create ConfigMap for api subdirectory
echo "Creating ConfigMap for 'api' subdirectory..."
kubectl create configmap nginx-lua-scripts-api --from-file=api/

# Create ConfigMap for wrk2-api subdirectory  
echo "Creating ConfigMap for 'wrk2-api' subdirectory..."
kubectl create configmap nginx-lua-scripts-wrk2-api --from-file=wrk2-api/

# Verify
echo ""
echo "ConfigMaps created:"
kubectl get configmap | grep nginx-lua-scripts

echo ""
echo "✓ ConfigMaps created! Now we need to update the deployment to mount both."
echo ""
echo "NOTE: The deployment needs to be updated to mount both ConfigMaps."
echo "This is more complex - we should try a simpler approach first."

