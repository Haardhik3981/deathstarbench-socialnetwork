#!/bin/bash

# Simple fix: Create ConfigMap by explicitly including all files from subdirectories

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Fixing nginx-lua-scripts ConfigMap ==="
echo ""

# Delete old ConfigMap
echo "Deleting old ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null || echo "Didn't exist"

echo ""
echo "Creating ConfigMap with all Lua files from subdirectories..."

# Change to the lua-scripts directory and create ConfigMap from there
# This preserves the directory structure
cd "${LUA_SCRIPTS_DIR}"

# Create ConfigMap - kubectl should handle subdirectories
kubectl create configmap nginx-lua-scripts --from-file=.

# Verify
echo ""
echo "Checking ConfigMap..."
sleep 2

# List what's in the ConfigMap
FILES_IN_CM=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null)

if [ -n "$FILES_IN_CM" ]; then
    FILE_COUNT=$(echo "$FILES_IN_CM" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
    echo "✓ ConfigMap created with $FILE_COUNT files"
    
    if [ "$FILE_COUNT" != "0" ] && [ "$FILE_COUNT" != "?" ]; then
        echo ""
        echo "Restarting nginx-thrift..."
        kubectl rollout restart deployment/nginx-thrift-deployment
        echo "✓ Done! Monitor with: kubectl get pods -l app=nginx-thrift -w"
    else
        echo ""
        echo "WARNING: Still showing 0 files. Trying manual approach..."
        
        # Manual approach: create ConfigMap with explicit file paths
        cd "${LUA_SCRIPTS_DIR}"
        kubectl delete configmap nginx-lua-scripts 2>/dev/null
        
        # Find all files and add them explicitly
        find . -type f -name "*.lua" | while read file; do
            key=$(echo "$file" | sed 's|^\./||')
            kubectl create configmap nginx-lua-scripts \
              --from-file="$key=$file" \
              --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || \
            kubectl create configmap nginx-lua-scripts \
              --from-file="$key=$file" --dry-run=client -o yaml | kubectl apply -f -
        done
    fi
else
    echo "ERROR: Could not create ConfigMap"
fi

cd "${PROJECT_ROOT}"

