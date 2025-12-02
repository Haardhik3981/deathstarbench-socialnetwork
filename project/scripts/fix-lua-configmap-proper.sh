#!/bin/bash

# Fix nginx-lua-scripts ConfigMap using a temporary directory approach

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing nginx-lua-scripts ConfigMap ===${NC}"
echo ""

# Create temporary directory that mirrors the structure
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Copy files to temp directory, flattening the structure but preserving paths in filenames
echo "Copying Lua files with flattened names..."
cd "${LUA_SCRIPTS_DIR}"

for file in $(find . -type f -name "*.lua"); do
    # Create a valid ConfigMap key by replacing / with _
    key=$(echo "$file" | sed 's|^\./||' | sed 's|/|_|g')
    cp "$file" "${TEMP_DIR}/${key}"
done

cd "${PROJECT_ROOT}"

FILE_COUNT=$(ls -1 "${TEMP_DIR}" | wc -l | tr -d ' ')
echo "Copied $FILE_COUNT files to temp directory"

# Delete old ConfigMap
echo ""
echo "Deleting old ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "✓ Deleted" || echo "Didn't exist"

# Create ConfigMap from temp directory
echo ""
echo "Creating ConfigMap from flattened files..."
kubectl create configmap nginx-lua-scripts --from-file="${TEMP_DIR}/"

# Cleanup
rm -rf "${TEMP_DIR}"

# Verify
echo ""
echo "Verifying ConfigMap..."
sleep 2
kubectl get configmap nginx-lua-scripts

DATA_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l | tr -d ' ')

if [ "$DATA_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ SUCCESS! ConfigMap has $DATA_COUNT files${NC}"
    echo ""
    echo "However, files are flattened. We need an init container or script to recreate directory structure."
    echo ""
    echo "For now, let's check if nginx-thrift can work with this..."
    kubectl rollout restart deployment/nginx-thrift-deployment
    echo "✓ Deployment restarted"
else
    echo -e "${YELLOW}Still showing 0 files${NC}"
fi

