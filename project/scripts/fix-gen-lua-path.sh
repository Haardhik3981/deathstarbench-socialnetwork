#!/bin/bash

# Quick fix for gen-lua mount path

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_section() { echo -e "${BLUE}=== $1 ===${NC}"; }

print_section "Fixing gen-lua mount path"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOYMENT_FILE="${PROJECT_ROOT}/kubernetes/deployments/nginx-thrift-deployment.yaml"

# Fix the mount path
if grep -q "mountPath: /usr/local/openresty/nginx/gen-lua" "$DEPLOYMENT_FILE"; then
    print_info "Updating gen-lua mount path to /gen-lua"
    sed -i.bak 's|mountPath: /usr/local/openresty/nginx/gen-lua|mountPath: /gen-lua|g' "$DEPLOYMENT_FILE"
    rm -f "${DEPLOYMENT_FILE}.bak"
    print_info "✓ Fixed!"
else
    print_info "Path already correct or different format"
fi

# Apply and restart
print_info "Applying fixed deployment..."
kubectl apply -f "$DEPLOYMENT_FILE"

print_info "Restarting deployment..."
kubectl rollout restart deployment/nginx-thrift-deployment

print_info "✓ Fix applied! Monitor with: kubectl get pods -l app=nginx-thrift -w"

