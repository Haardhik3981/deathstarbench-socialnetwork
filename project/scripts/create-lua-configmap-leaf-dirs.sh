#!/bin/bash

# SOLUTION: Create ConfigMaps for each leaf directory
# Mount them at the full path (e.g., api/user/, api/post/, etc.)
# This avoids the slash-in-key problem

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMaps (Leaf Directory Method) ==="
echo ""
echo "This creates separate ConfigMaps for each subdirectory (user/, post/, etc.)"
echo "and mounts them at the correct paths."
echo ""

# Verify source directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "ERROR: Lua scripts directory not found"
    exit 1
fi

# Delete ALL old ConfigMaps
echo "Deleting existing ConfigMaps..."
kubectl delete configmap nginx-lua-scripts-api 2>/dev/null || true
kubectl delete configmap nginx-lua-scripts-wrk2-api 2>/dev/null || true
kubectl delete configmap nginx-lua-scripts 2>/dev/null || true
# Delete any leaf directory ConfigMaps
kubectl get configmap -o name | grep "nginx-lua-scripts-" | xargs kubectl delete 2>/dev/null || true

cd "${LUA_SCRIPTS_DIR}"

# Find all subdirectories that contain .lua files
echo "Finding subdirectories with Lua files..."

# For api/
if [ -d "api" ]; then
    echo ""
    echo "Processing api/ subdirectories..."
    for subdir in api/*/; do
        if [ -d "$subdir" ] && [ "$(find "$subdir" -name "*.lua" | wc -l)" -gt 0 ]; then
            # Get subdirectory name (e.g., "api/user" -> "user")
            dirname=$(basename "$subdir")
            cm_name="nginx-lua-scripts-api-${dirname}"
            
            echo "  Creating $cm_name from $subdir..."
            cd "$subdir"
            kubectl create configmap "$cm_name" --from-file=.
            cd "${LUA_SCRIPTS_DIR}"
            echo "    ✓ Created"
        fi
    done
fi

# For wrk2-api/
if [ -d "wrk2-api" ]; then
    echo ""
    echo "Processing wrk2-api/ subdirectories..."
    for subdir in wrk2-api/*/; do
        if [ -d "$subdir" ] && [ "$(find "$subdir" -name "*.lua" | wc -l)" -gt 0 ]; then
            dirname=$(basename "$subdir")
            cm_name="nginx-lua-scripts-wrk2-api-${dirname}"
            
            echo "  Creating $cm_name from $subdir..."
            cd "$subdir"
            kubectl create configmap "$cm_name" --from-file=.
            cd "${LUA_SCRIPTS_DIR}"
            echo "    ✓ Created"
        fi
    done
fi

cd "${PROJECT_ROOT}"

# List created ConfigMaps
echo ""
echo "Created ConfigMaps:"
kubectl get configmap | grep "nginx-lua-scripts-" || echo "  (none found)"

echo ""
echo "⚠ IMPORTANT: This approach requires updating the deployment to mount"
echo "each ConfigMap at its specific path (e.g., api/user/, wrk2-api/user/, etc.)"
echo ""
echo "This is complex. Let me create a simpler solution..."

