#!/bin/bash

# Fix nginx-lua-scripts ConfigMap by explicitly adding each file

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing nginx-lua-scripts ConfigMap (Explicit Method) ===${NC}"
echo ""

# Verify directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "Error: Directory not found: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

# Delete old ConfigMap
echo "Deleting old ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "✓ Deleted" || echo "Didn't exist"

echo ""
echo "Finding all Lua files..."
cd "${LUA_SCRIPTS_DIR}"

# Find all .lua files with their relative paths
FILES=$(find . -type f -name "*.lua")

if [ -z "$FILES" ]; then
    echo "Error: No .lua files found!"
    exit 1
fi

FILE_COUNT=$(echo "$FILES" | wc -l | tr -d ' ')
echo "Found $FILE_COUNT Lua files"
echo ""

# Build kubectl command with all files
echo "Creating ConfigMap by explicitly adding each file..."
BUILD_ARGS=""

# First pass: collect all files with their paths
for file in $FILES; do
    # Remove leading ./
    key=$(echo "$file" | sed 's|^\./||')
    BUILD_ARGS="${BUILD_ARGS} --from-file=${key}=${file}"
done

# Create ConfigMap in one command with all files
echo "Running kubectl create configmap with all files..."
kubectl create configmap nginx-lua-scripts $BUILD_ARGS

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMap..."
sleep 2

# Check DATA field directly
DATA_FIELD=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null)

if [ -n "$DATA_FIELD" ] && [ "$DATA_FIELD" != "{}" ] && [ "$DATA_FIELD" != "null" ]; then
    # Try to count files
    FILE_COUNT_IN_CM=$(echo "$DATA_FIELD" | python3 -c "import sys, json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || \
                       echo "$DATA_FIELD" | grep -o '"[^"]*":' | wc -l | tr -d ' ')
    
    if [ "$FILE_COUNT_IN_CM" -gt 0 ]; then
        echo -e "${GREEN}✓ SUCCESS! ConfigMap has $FILE_COUNT_IN_CM files${NC}"
        echo ""
        echo "Files in ConfigMap:"
        echo "$DATA_FIELD" | python3 -c "import sys, json; d=json.load(sys.stdin); [print(f'  - {k}') for k in sorted(d.keys())]" 2>/dev/null | head -15
        
        echo ""
        echo "Restarting nginx-thrift..."
        kubectl rollout restart deployment/nginx-thrift-deployment
        echo -e "${GREEN}✓ Done!${NC}"
    else
        echo -e "${YELLOW}Warning: Count shows 0 but data exists. Checking details...${NC}"
        kubectl get configmap nginx-lua-scripts -o yaml | head -50
    fi
else
    echo -e "${YELLOW}ERROR: ConfigMap still appears empty${NC}"
    echo ""
    echo "Checking ConfigMap details:"
    kubectl get configmap nginx-lua-scripts -o yaml
fi

