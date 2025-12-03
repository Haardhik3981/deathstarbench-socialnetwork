#!/bin/bash

# Create ConfigMap for nginx Lua scripts
# This version uses kubectl create with explicit file paths
# Kubernetes ConfigMaps DO support slashes in keys when created from directory

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMap ==="
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
    echo "ERROR: No files found in Lua scripts directory!"
    exit 1
fi

# Delete old ConfigMap
echo ""
echo "Deleting existing ConfigMap (if any)..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "✓ Deleted" || echo "  (didn't exist)"

# Method: Use kubectl create with --from-file and directory
# When you use --from-file with a directory, kubectl creates keys with the relative paths
echo ""
echo "Creating ConfigMap from directory..."
cd "${LUA_SCRIPTS_DIR}"

# The key insight: kubectl --from-file=. creates keys with paths including slashes
# These ARE valid when the ConfigMap is created this way (kubectl handles it)
# When mounted, Kubernetes creates the directory structure
kubectl create configmap nginx-lua-scripts --from-file=.

cd "${PROJECT_ROOT}"

# Verify by checking if we can get the data
echo ""
echo "Verifying ConfigMap..."
sleep 1

# Check if ConfigMap exists
if ! kubectl get configmap nginx-lua-scripts >/dev/null 2>&1; then
    echo "✗ ERROR: ConfigMap was not created"
    exit 1
fi

# Get the ConfigMap and check for data
CM_JSON=$(kubectl get configmap nginx-lua-scripts -o json 2>/dev/null)

if [ -z "$CM_JSON" ]; then
    echo "✗ ERROR: Could not retrieve ConfigMap"
    exit 1
fi

# Check if data field exists and is not empty
DATA_EXISTS=$(echo "$CM_JSON" | jq -r '.data // empty' 2>/dev/null || echo "")

if [ -z "$DATA_EXISTS" ] || [ "$DATA_EXISTS" = "null" ] || [ "$DATA_EXISTS" = "{}" ]; then
    echo "⚠ WARNING: ConfigMap created but data section appears empty"
    echo ""
    echo "Checking ConfigMap YAML:"
    kubectl get configmap nginx-lua-scripts -o yaml | head -50
    echo ""
    echo "This might mean kubectl didn't read the files correctly."
    echo "Trying alternative verification..."
    
    # Try to list keys using kubectl describe
    echo ""
    echo "Trying kubectl describe:"
    kubectl describe configmap nginx-lua-scripts | head -30
else
    # Count keys in data
    KEY_COUNT=$(echo "$CM_JSON" | jq '.data | keys | length' 2>/dev/null || echo "0")
    
    if [ "$KEY_COUNT" -gt 0 ]; then
        echo "✓ SUCCESS! ConfigMap created with $KEY_COUNT files"
        echo ""
        echo "Sample files in ConfigMap:"
        echo "$CM_JSON" | jq -r '.data | keys[]' 2>/dev/null | head -5
        echo ""
        echo "Restarting nginx-thrift deployment..."
        kubectl rollout restart deployment/nginx-thrift-deployment
        echo "✓ Deployment restarted!"
        echo ""
        echo "Waiting for rollout..."
        kubectl rollout status deployment/nginx-thrift-deployment --timeout=60s 2>&1 || echo "  (check status with: kubectl get pods -l app=nginx-thrift)"
        echo ""
        echo "✓ Done! To verify files are mounted in the pod:"
        echo "  kubectl exec -it \$(kubectl get pod -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}') -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/user/"
    else
        echo "⚠ ConfigMap has data section but appears to have 0 keys"
        echo "Full JSON:"
        echo "$CM_JSON" | jq '.' | head -50
    fi
fi

