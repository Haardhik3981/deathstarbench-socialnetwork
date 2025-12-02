#!/bin/bash

# Simple fix: Create ConfigMap from parent directory
# This should preserve directory structure

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_WEB_SERVER_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server"

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
echo "=== Fixing nginx-lua-scripts ConfigMap (Simple Method) ==="
echo ""

# Verify source exists
if [ ! -d "${NGINX_WEB_SERVER_DIR}/lua-scripts" ]; then
    print_error "Lua scripts directory not found: ${NGINX_WEB_SERVER_DIR}/lua-scripts"
    exit 1
fi

# Count files
FILE_COUNT=$(find "${NGINX_WEB_SERVER_DIR}/lua-scripts" -type f | wc -l | tr -d ' ')
print_info "Found $FILE_COUNT files in lua-scripts directory"

if [ "$FILE_COUNT" -eq 0 ]; then
    print_error "No files found!"
    exit 1
fi

# Delete existing ConfigMap
print_info "Deleting existing ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && print_info "✓ Deleted" || print_warn "Didn't exist"

# Create ConfigMap from parent directory
# This should preserve the lua-scripts/ directory structure
print_info "Creating ConfigMap from parent directory..."
cd "${NGINX_WEB_SERVER_DIR}"

# Try creating from parent directory - this should create keys like "lua-scripts/api/..."
kubectl create configmap nginx-lua-scripts --from-file=lua-scripts/

cd "${PROJECT_ROOT}"

# Verify
print_info ""
print_info "Verifying ConfigMap..."
sleep 2

# Check what keys were created
print_info "Checking ConfigMap keys..."
KEYS=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null)

if [ -n "$KEYS" ] && [ "$KEYS" != "{}" ] && [ "$KEYS" != "null" ]; then
    if command -v python3 &> /dev/null; then
        DATA_COUNT=$(echo "$KEYS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")
        print_info "✓ ConfigMap created with $DATA_COUNT files"
        echo ""
        print_info "Sample keys:"
        echo "$KEYS" | python3 -c "import sys, json; d=json.load(sys.stdin); [print('  -', k) for k in list(d.keys())[:5]]" 2>/dev/null || true
    else
        DATA_COUNT=$(echo "$KEYS" | grep -o '"[^"]*":' | wc -l | tr -d ' ')
        print_info "✓ ConfigMap created with $DATA_COUNT files"
    fi
    
    if [ "$DATA_COUNT" -gt 0 ]; then
        echo ""
        print_info "Restarting nginx-thrift deployment..."
        kubectl rollout restart deployment/nginx-thrift-deployment
        print_info "✓ Done! Wait 30-60 seconds for the pod to restart."
        echo ""
        print_info "Note: If keys have 'lua-scripts/' prefix, the deployment mount path should handle it."
    else
        print_error "ConfigMap appears empty!"
        kubectl get configmap nginx-lua-scripts -o yaml | head -40
        exit 1
    fi
else
    print_error "ConfigMap appears empty!"
    print_warn "Showing ConfigMap YAML for debugging:"
    kubectl get configmap nginx-lua-scripts -o yaml | head -40
    exit 1
fi

