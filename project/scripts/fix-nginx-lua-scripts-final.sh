#!/bin/bash

# Fix nginx-lua-scripts ConfigMap - include all files from subdirectories

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"
LUA_SCRIPTS_DIR="${DSB_ROOT}/nginx-web-server/lua-scripts"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo -e "${BLUE}=== Fixing nginx-lua-scripts ConfigMap ===${NC}"
echo ""

# Verify source exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    print_warn "Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

print_info "Source directory: ${LUA_SCRIPTS_DIR}"

# Find all files
FILES=$(find "${LUA_SCRIPTS_DIR}" -type f)
FILE_COUNT=$(echo "$FILES" | grep -v "^$" | wc -l | tr -d ' ')

print_info "Found $FILE_COUNT Lua files"

if [ "$FILE_COUNT" -eq 0 ]; then
    print_warn "No files found!"
    exit 1
fi

# Delete existing ConfigMap
print_info ""
print_info "Deleting existing ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && print_info "✓ Deleted" || print_warn "Didn't exist"

# Create ConfigMap with all files
# Use --from-file with directory to preserve structure recursively
print_info ""
print_info "Creating ConfigMap with all files (including subdirectories)..."

cd "${LUA_SCRIPTS_DIR}"

# Create ConfigMap - kubectl should handle subdirectories recursively
kubectl create configmap nginx-lua-scripts \
  --from-file=.

cd "${PROJECT_ROOT}"

# Verify
print_info ""
print_info "Verifying ConfigMap..."
sleep 2

# Count files in ConfigMap
CM_DATA=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null)

if [ -n "$CM_DATA" ] && [ "$CM_DATA" != "{}" ]; then
    # Count keys in JSON
    FILE_COUNT_IN_CM=$(echo "$CM_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")
    
    if [ "$FILE_COUNT_IN_CM" -gt 0 ]; then
        print_info "✓ SUCCESS! ConfigMap has $FILE_COUNT_IN_CM files"
        echo ""
        print_info "Sample files in ConfigMap:"
        echo "$CM_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); [print(f'  - {k}') for k in list(d.keys())[:10]]" 2>/dev/null || echo "  (could not list)"
        
        echo ""
        print_info "Restarting nginx-thrift deployment..."
        kubectl rollout restart deployment/nginx-thrift-deployment
        print_info "✓ Deployment restart initiated"
        echo ""
        print_info "Monitor the pod:"
        echo "  kubectl get pods -l app=nginx-thrift -w"
    else
        print_warn "ConfigMap still appears empty"
        print_info "Let's check what's in it:"
        kubectl get configmap nginx-lua-scripts -o yaml | head -30
    fi
else
    print_warn "ConfigMap appears empty"
    print_info "Checking ConfigMap details:"
    kubectl get configmap nginx-lua-scripts
    kubectl describe configmap nginx-lua-scripts
fi

