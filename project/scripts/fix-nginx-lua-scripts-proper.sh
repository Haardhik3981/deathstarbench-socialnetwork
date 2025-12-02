#!/bin/bash

# Fix nginx-lua-scripts ConfigMap - properly include subdirectories

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"
LUA_SCRIPTS_DIR="${DSB_ROOT}/nginx-web-server/lua-scripts"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Verify source exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    print_warn "Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

print_info "Found Lua scripts directory: ${LUA_SCRIPTS_DIR}"

# Count files first
FILE_COUNT=$(find "${LUA_SCRIPTS_DIR}" -type f | wc -l | tr -d ' ')
print_info "Found $FILE_COUNT Lua files in subdirectories"

if [ "$FILE_COUNT" -eq 0 ]; then
    print_warn "No files found! Check the directory structure."
    exit 1
fi

print_info ""
print_info "Deleting existing ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && print_info "✓ Deleted" || print_warn "ConfigMap doesn't exist"

print_info ""
print_info "Creating ConfigMap with all files (including subdirectories)..."

# Create ConfigMap by finding all files and adding them with their relative paths
# This preserves the directory structure
cd "${LUA_SCRIPTS_DIR}"

# Build kubectl command with all files
FILES=$(find . -type f)
FILE_ARGS=""

for file in $FILES; do
    # Remove leading ./
    clean_path=$(echo "$file" | sed 's|^\./||')
    FILE_ARGS="${FILE_ARGS} --from-file=${clean_path}=${file}"
done

# Create the ConfigMap with all files
kubectl create configmap nginx-lua-scripts $FILE_ARGS

cd "${PROJECT_ROOT}"

# Verify
print_info ""
print_info "Verifying ConfigMap..."
sleep 2
NEW_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || \
            kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l | tr -d ' ')

print_info "ConfigMap now has $NEW_COUNT files"

if [ "$NEW_COUNT" -gt 0 ]; then
    print_info ""
    print_info "✓ SUCCESS! ConfigMap created with $NEW_COUNT files"
    print_info ""
    print_info "Listing files in ConfigMap:"
    kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | python3 -c "import sys, json; [print(k) for k in json.load(sys.stdin).keys()]" 2>/dev/null | head -10 || \
    kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | head -10 | sed 's/":$//' | sed 's/^"//'
    
    print_info ""
    print_info "Restarting nginx-thrift deployment..."
    kubectl rollout restart deployment/nginx-thrift-deployment
    print_info "✓ Deployment restart initiated"
else
    print_warn "ConfigMap still appears empty. Trying alternative method..."
    
    # Alternative: use --from-file with directory (should work recursively)
    kubectl delete configmap nginx-lua-scripts 2>/dev/null
    kubectl create configmap nginx-lua-scripts \
      --from-file="${LUA_SCRIPTS_DIR}/" \
      --dry-run=client -o yaml | kubectl apply -f -
    
    sleep 2
    ALT_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l | tr -d ' ')
    print_info "Alternative method: $ALT_COUNT files"
fi

