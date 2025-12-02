#!/bin/bash

# Complete fix for nginx-thrift - recreate empty Lua scripts ConfigMap

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"

print_section "Fixing nginx-thrift - Empty Lua Scripts ConfigMap"

# Check if DeathStarBench source exists
if [ ! -d "${DSB_ROOT}/nginx-web-server/lua-scripts" ]; then
    print_warn "DeathStarBench source not found at expected path: ${DSB_ROOT}"
    print_info "Trying alternative paths..."
    
    # Try other possible locations
    ALTERNATIVE_PATHS=(
        "${PROJECT_ROOT}/../../socialNetwork"
        "${PROJECT_ROOT}/../../DeathStarBench/socialNetwork"
        "${PROJECT_ROOT}/../DeathStarBench/socialNetwork"
    )
    
    FOUND=0
    for path in "${ALTERNATIVE_PATHS[@]}"; do
        if [ -d "${path}/nginx-web-server/lua-scripts" ]; then
            DSB_ROOT="${path}"
            print_info "Found at: ${DSB_ROOT}"
            FOUND=1
            break
        fi
    done
    
    if [ $FOUND -eq 0 ]; then
        print_warn "Could not find DeathStarBench source. Please provide the path:"
        read -p "Enter path to DeathStarBench socialNetwork directory: " DSB_ROOT
        if [ ! -d "${DSB_ROOT}/nginx-web-server/lua-scripts" ]; then
            print_warn "Still not found. Exiting."
            exit 1
        fi
    fi
fi

LUA_SCRIPTS_DIR="${DSB_ROOT}/nginx-web-server/lua-scripts"

print_info "Using Lua scripts from: ${LUA_SCRIPTS_DIR}"

# Verify directory has files
FILE_COUNT=$(find "${LUA_SCRIPTS_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -eq 0 ]; then
    print_warn "No files found in ${LUA_SCRIPTS_DIR}"
    exit 1
fi

print_info "Found $FILE_COUNT files in lua-scripts directory"

# Delete existing empty ConfigMap
print_info ""
print_info "Deleting empty nginx-lua-scripts ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && print_info "✓ Deleted" || print_warn "ConfigMap doesn't exist or already deleted"

# Recreate ConfigMap with all files
print_info ""
print_info "Creating nginx-lua-scripts ConfigMap from directory..."
kubectl create configmap nginx-lua-scripts \
  --from-file="${LUA_SCRIPTS_DIR}/"

# Verify
print_info ""
print_info "Verifying ConfigMap..."
sleep 2
NEW_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l | tr -d ' ')
print_info "ConfigMap now has $NEW_COUNT files"

if [ "$NEW_COUNT" -gt 0 ]; then
    print_info "✓ Success! ConfigMap recreated with $NEW_COUNT files"
    print_info ""
    print_info "Restarting nginx-thrift to pick up the new ConfigMap..."
    kubectl rollout restart deployment/nginx-thrift-deployment
    print_info "✓ Deployment restart initiated"
    print_info ""
    print_info "Monitor the pod:"
    echo "  kubectl get pods -l app=nginx-thrift -w"
else
    print_warn "ConfigMap still appears empty. Check the source directory."
fi

