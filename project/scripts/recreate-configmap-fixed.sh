#!/bin/bash

# Script to properly recreate the deathstarbench-config ConfigMap with all files

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
if [ ! -d "${DSB_ROOT}" ]; then
    print_error "DeathStarBench source not found at: ${DSB_ROOT}"
    exit 1
fi

print_info "Recreating deathstarbench-config ConfigMap with all required files..."
print_info "Source directory: ${DSB_ROOT}"

# Delete existing ConfigMap
print_info "Deleting existing ConfigMap..."
kubectl delete configmap deathstarbench-config 2>/dev/null || print_warn "ConfigMap doesn't exist, creating new one"

# Create ConfigMap with ALL files at once
print_info "Creating ConfigMap with all files..."
kubectl create configmap deathstarbench-config \
  --from-file=service-config.json="${DSB_ROOT}/config/service-config.json" \
  --from-file=jaeger-config.yml="${DSB_ROOT}/config/jaeger-config.yml" \
  --from-file=nginx.conf="${DSB_ROOT}/nginx-web-server/conf/nginx.conf" \
  --from-file=jaeger-config.json="${DSB_ROOT}/nginx-web-server/jaeger-config.json"

# Verify it was created with multiple files
FILE_COUNT=$(kubectl get configmap deathstarbench-config -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l)
print_info "ConfigMap created with $FILE_COUNT files"

# Verify each file exists
print_info "Verifying files in ConfigMap..."
for file in service-config.json jaeger-config.yml nginx.conf jaeger-config.json; do
    if kubectl get configmap deathstarbench-config -o jsonpath="{.data.${file}}" > /dev/null 2>&1; then
        print_info "  ✓ $file"
    else
        print_error "  ✗ $file MISSING"
    fi
done

print_info ""
print_info "ConfigMap recreated successfully!"
print_info "Now restart the deployments to pick up the new ConfigMap:"
echo ""
echo "  kubectl rollout restart deployment/compose-post-service-deployment"
echo "  kubectl rollout restart deployment/user-service-deployment"
echo "  # ... restart all service deployments"

