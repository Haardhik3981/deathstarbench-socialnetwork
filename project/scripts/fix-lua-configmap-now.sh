#!/bin/bash

# Quick fix for nginx-lua-scripts ConfigMap - explicitly add all files

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
echo "=== Fixing nginx-lua-scripts ConfigMap ==="
echo ""

# Verify source exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    print_error "Lua scripts directory not found: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

# Count files
FILE_COUNT=$(find "${LUA_SCRIPTS_DIR}" -type f | wc -l | tr -d ' ')
print_info "Found $FILE_COUNT files in ${LUA_SCRIPTS_DIR}"

if [ "$FILE_COUNT" -eq 0 ]; then
    print_error "No files found!"
    exit 1
fi

# Delete existing ConfigMap
print_info "Deleting existing ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && print_info "✓ Deleted" || print_warn "Didn't exist"

# Create ConfigMap by including subdirectories separately
# Using --from-file on directories allows kubectl to handle subdirectories
# and create keys with '/' (this is allowed when created from directories)
print_info "Creating ConfigMap with api and wrk2-api subdirectories..."
cd "${LUA_SCRIPTS_DIR}"

# Use --from-file on each subdirectory
# kubectl will recursively include files and preserve paths in keys
kubectl create configmap nginx-lua-scripts \
  --from-file=api \
  --from-file=wrk2-api

cd "${PROJECT_ROOT}"

# Verify
print_info ""
print_info "Verifying ConfigMap..."
sleep 2

# Check using kubectl get to see DATA count
# Try python first, fallback to grep
DATA_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null | python3 -c "import sys, json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || \
            kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l | tr -d ' ')

if [ "$DATA_COUNT" -gt 0 ]; then
    print_info "✓ SUCCESS! ConfigMap has $DATA_COUNT files"
    echo ""
    print_info "Sample files:"
    kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | python3 -c "import sys, json; [print('  -', k) for k in list(json.load(sys.stdin).keys())[:5]]" 2>/dev/null || \
    kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | head -5 | sed 's/":$//' | sed 's/^"//' | sed 's/^/  - /'
    echo ""
    print_info "Restarting nginx-thrift deployment..."
    kubectl rollout restart deployment/nginx-thrift-deployment
    print_info "✓ Done! Wait 30-60 seconds for the pod to restart."
else
    print_error "ConfigMap still appears empty!"
    echo ""
    print_warn "Showing ConfigMap YAML for debugging:"
    kubectl get configmap nginx-lua-scripts -o yaml | head -40
    exit 1
fi
