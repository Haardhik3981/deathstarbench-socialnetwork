#!/bin/bash

# Fix nginx-lua-scripts ConfigMap (it shows 0 data files)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"

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

# Verify source exists
if [ ! -d "${DSB_ROOT}/nginx-web-server/lua-scripts" ]; then
    print_error "Lua scripts directory not found at: ${DSB_ROOT}/nginx-web-server/lua-scripts"
    exit 1
fi

print_info "Checking lua-scripts directory..."
ls -la "${DSB_ROOT}/nginx-web-server/lua-scripts/" | head -20

print_info ""
print_info "Recreating nginx-lua-scripts ConfigMap..."
print_info "Source: ${DSB_ROOT}/nginx-web-server/lua-scripts/"

# Delete existing ConfigMap
kubectl delete configmap nginx-lua-scripts 2>/dev/null || print_warn "ConfigMap doesn't exist"

# Create ConfigMap from directory
# This will preserve directory structure
kubectl create configmap nginx-lua-scripts \
  --from-file="${DSB_ROOT}/nginx-web-server/lua-scripts/"

# Verify
FILE_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l)
print_info "ConfigMap created with $FILE_COUNT files"

# List some files to verify
print_info "Files in ConfigMap:"
kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | head -10 | sed 's/":$//' | sed 's/^"//'

print_info ""
print_info "✓ nginx-lua-scripts ConfigMap recreated!"
print_info "Restart nginx-thrift to pick up the new ConfigMap:"
echo ""
echo "  kubectl rollout restart deployment/nginx-thrift-deployment"

