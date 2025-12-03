#!/bin/bash

# FINAL SOLUTION: Create ConfigMaps from each leaf directory
# Mount them at the full paths (e.g., api/user/, wrk2-api/user/, etc.)
# This works because --from-file=. from a leaf directory includes all files

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMaps (Leaf Directory Solution) ==="
echo ""
echo "Creating separate ConfigMaps for each subdirectory (user/, post/, etc.)"
echo "and mounting them at the correct paths."
echo ""

# Verify source directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "ERROR: Lua scripts directory not found"
    exit 1
fi

# Delete ALL old ConfigMaps
echo "Deleting existing ConfigMaps..."
kubectl get configmap -o name 2>/dev/null | grep "nginx-lua-scripts" | xargs kubectl delete 2>/dev/null || true

cd "${LUA_SCRIPTS_DIR}"

CONFIGMAPS_CREATED=0

# Process api/ subdirectories
if [ -d "api" ]; then
    echo "Processing api/ subdirectories..."
    for subdir in api/*/; do
        if [ -d "$subdir" ] && [ "$(find "$subdir" -name "*.lua" -type f | wc -l)" -gt 0 ]; then
            dirname=$(basename "$subdir")
            cm_name="nginx-lua-scripts-api-${dirname}"
            
            echo "  Creating $cm_name from $subdir..."
            cd "$subdir"
            kubectl create configmap "$cm_name" --from-file=.
            cd "${LUA_SCRIPTS_DIR}"
            CONFIGMAPS_CREATED=$((CONFIGMAPS_CREATED + 1))
            echo "    ✓ Created"
        fi
    done
fi

# Process wrk2-api/ subdirectories
if [ -d "wrk2-api" ]; then
    echo ""
    echo "Processing wrk2-api/ subdirectories..."
    for subdir in wrk2-api/*/; do
        if [ -d "$subdir" ] && [ "$(find "$subdir" -name "*.lua" -type f | wc -l)" -gt 0 ]; then
            dirname=$(basename "$subdir")
            cm_name="nginx-lua-scripts-wrk2-api-${dirname}"
            
            echo "  Creating $cm_name from $subdir..."
            cd "$subdir"
            kubectl create configmap "$cm_name" --from-file=.
            cd "${LUA_SCRIPTS_DIR}"
            CONFIGMAPS_CREATED=$((CONFIGMAPS_CREATED + 1))
            echo "    ✓ Created"
        fi
    done
fi

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMaps..."
sleep 2

CREATED_CM=$(kubectl get configmap -o name | grep "nginx-lua-scripts" | wc -l | tr -d ' ')

echo ""
echo "✓ Created $CREATED_CM ConfigMaps"
echo ""
echo "ConfigMaps created:"
kubectl get configmap | grep "nginx-lua-scripts" || echo "  (none found)"

echo ""
echo "⚠ NEXT STEP: Update the deployment to mount each ConfigMap at its path"
echo "For example:"
echo "  - nginx-lua-scripts-api-user at /usr/local/openresty/nginx/lua-scripts/api/user"
echo "  - nginx-lua-scripts-wrk2-api-user at /usr/local/openresty/nginx/lua-scripts/wrk2-api/user"
echo ""
echo "I'll create a script to update the deployment automatically..."

