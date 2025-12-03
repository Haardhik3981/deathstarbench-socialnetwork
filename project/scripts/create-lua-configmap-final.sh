#!/bin/bash

# FINAL SOLUTION: Create ConfigMap using kubectl's --from-file with directory
# This SHOULD work - kubectl handles subdirectories and creates keys with paths
# When mounted, Kubernetes creates the directory structure automatically
# The key is to use the directory path, not change into it

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMap (Final Method) ==="
echo ""

# Verify source directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "ERROR: Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

# Count files
FILE_COUNT=$(find "${LUA_SCRIPTS_DIR}" -type f | wc -l | tr -d ' ')
echo "Found $FILE_COUNT Lua files in source directory"

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "ERROR: No files found!"
    exit 1
fi

# Delete old ConfigMap
echo ""
echo "Deleting existing ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "✓ Deleted" || echo "  (didn't exist)"

# The key insight: Use --from-file with the directory PATH, not change into it
# kubectl should handle subdirectories recursively
echo ""
echo "Creating ConfigMap from directory..."
echo "Using: kubectl create configmap --from-file=${LUA_SCRIPTS_DIR}"

# Create ConfigMap - kubectl should preserve directory structure
if kubectl create configmap nginx-lua-scripts --from-file="${LUA_SCRIPTS_DIR}" 2>&1; then
    echo "✓ ConfigMap created"
else
    echo "✗ Failed with directory path, trying from within directory..."
    cd "${LUA_SCRIPTS_DIR}"
    if kubectl create configmap nginx-lua-scripts --from-file=. 2>&1; then
        echo "✓ ConfigMap created (from within directory)"
        cd "${PROJECT_ROOT}"
    else
        echo "✗ Both methods failed"
        cd "${PROJECT_ROOT}"
        exit 1
    fi
fi

# Now verify by checking if we can see any data
echo ""
echo "Verifying ConfigMap..."
sleep 2

# Get the ConfigMap and check
CM_OUTPUT=$(kubectl get configmap nginx-lua-scripts -o yaml 2>/dev/null)

if [ -z "$CM_OUTPUT" ]; then
    echo "✗ ERROR: ConfigMap not found"
    exit 1
fi

# Check if data section exists
if echo "$CM_OUTPUT" | grep -q "^data:"; then
    # Count non-empty lines after "data:" (rough estimate of keys)
    DATA_LINES=$(echo "$CM_OUTPUT" | sed -n '/^data:/,/^[a-z]/p' | grep -v '^data:' | grep -v '^[a-z]' | grep -v '^---' | grep -v '^$' | wc -l | tr -d ' ')
    
    if [ "$DATA_LINES" -gt 0 ]; then
        echo "✓ SUCCESS! ConfigMap has data section with content"
        echo ""
        echo "Sample of what was created:"
        echo "$CM_OUTPUT" | sed -n '/^data:/,/^[a-z]/p' | head -10
        echo ""
        echo "Restarting nginx-thrift deployment..."
        kubectl rollout restart deployment/nginx-thrift-deployment
        echo "✓ Deployment restarted!"
        echo ""
        echo "To verify files are accessible in the pod:"
        echo "  kubectl exec -it \$(kubectl get pod -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}') -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/user/"
    else
        echo "⚠ ConfigMap has data section but appears empty"
        echo "Full ConfigMap:"
        echo "$CM_OUTPUT"
    fi
else
    echo "✗ ERROR: ConfigMap created but 'data:' section is missing"
    echo "Full ConfigMap YAML:"
    echo "$CM_OUTPUT"
    echo ""
    echo "This suggests kubectl didn't read the files."
    echo "Trying to understand why..."
    echo ""
    echo "Files in source directory:"
    find "${LUA_SCRIPTS_DIR}" -type f | head -5
fi

