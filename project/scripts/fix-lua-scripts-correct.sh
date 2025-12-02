#!/bin/bash

# Create ConfigMap correctly - kubectl --from-file with directory DOES work recursively
# The issue might be that we're not in the right directory

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMap ==="
echo ""

# Verify files exist
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "Error: Directory not found: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

echo "Source directory: ${LUA_SCRIPTS_DIR}"
FILE_COUNT=$(find "${LUA_SCRIPTS_DIR}" -type f -name "*.lua" | wc -l | tr -d ' ')
echo "Found $FILE_COUNT Lua files"
echo ""

# Delete old
echo "Deleting old ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "✓ Deleted" || echo "Didn't exist"

# Create from parent directory, referencing the lua-scripts subdirectory
# This should preserve the api/ and wrk2-api/ structure
echo ""
echo "Creating ConfigMap (this may take a moment)..."
cd "${LUA_SCRIPTS_DIR}/.."

kubectl create configmap nginx-lua-scripts \
  --from-file=lua-scripts/

cd "${PROJECT_ROOT}"

# Verify  
echo ""
echo "Verifying ConfigMap..."
sleep 2
kubectl get configmap nginx-lua-scripts

# Check if it has data
DATA=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null)

if [ -n "$DATA" ] && [ "$DATA" != "{}" ] && [ "$DATA" != "null" ]; then
    COUNT=$(echo "$DATA" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
    if [ "$COUNT" != "?" ] && [ "$COUNT" -gt 0 ]; then
        echo ""
        echo "✓ SUCCESS! ConfigMap has $COUNT files"
        echo ""
        echo "Restarting nginx-thrift..."
        kubectl rollout restart deployment/nginx-thrift-deployment
        echo "✓ Done!"
    else
        echo ""
        echo "Checking ConfigMap YAML to see what's in it:"
        kubectl get configmap nginx-lua-scripts -o yaml | grep -A 5 "^data:" | head -20
    fi
else
    echo ""
    echo "ConfigMap still appears empty. Showing full YAML:"
    kubectl get configmap nginx-lua-scripts -o yaml
fi

