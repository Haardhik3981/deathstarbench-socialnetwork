#!/bin/bash

# Quick fix for nginx-thrift - fixes the config path and restarts

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_section() { echo -e "${BLUE}=== $1 ===${NC}"; }

print_section "Quick nginx-thrift Fix"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Fix the deployment YAML (change mount path)
print_info "Fixing nginx.conf mount path in deployment..."

DEPLOYMENT_FILE="${PROJECT_ROOT}/kubernetes/deployments/nginx-thrift-deployment.yaml"

if grep -q "mountPath: /etc/nginx/nginx.conf" "$DEPLOYMENT_FILE"; then
    print_info "Updating mount path from /etc/nginx/nginx.conf to /usr/local/openresty/nginx/conf/nginx.conf"
    sed -i.bak 's|mountPath: /etc/nginx/nginx.conf|mountPath: /usr/local/openresty/nginx/conf/nginx.conf|g' "$DEPLOYMENT_FILE"
    rm -f "${DEPLOYMENT_FILE}.bak"
    print_info "✓ Deployment YAML updated"
else
    print_warn "Mount path already fixed or different format"
fi

# Apply the fixed deployment
print_info "Applying fixed deployment..."
kubectl apply -f "$DEPLOYMENT_FILE"

# Wait a moment
sleep 5

# Restart the deployment
print_info "Restarting nginx-thrift deployment..."
kubectl rollout restart deployment/nginx-thrift-deployment

print_info "✓ Fix applied! Waiting for pod to restart..."
print_info "Monitor with: kubectl get pods -l app=nginx-thrift -w"
print_info "Or check logs: kubectl logs -l app=nginx-thrift -f"

