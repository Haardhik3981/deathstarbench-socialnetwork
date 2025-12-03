#!/bin/bash

# Fix Prometheus configuration for pod and node scraping

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_section() { echo -e "${BLUE}=== $1 ===${NC}"; }

print_section "Fixing Prometheus Configuration"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Step 1: Apply updated ConfigMap
print_section "Step 1: Updating Prometheus ConfigMap"
print_info "Applying updated prometheus-configmap.yaml..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml"

# Step 2: Apply updated RBAC permissions
print_section "Step 2: Updating Prometheus RBAC Permissions"
print_info "Applying updated prometheus-deployment.yaml (RBAC section)..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-deployment.yaml"

# Step 3: Restart Prometheus to pick up new config
print_section "Step 3: Restarting Prometheus"
print_info "Rolling out restart to pick up new configuration..."
kubectl rollout restart deployment/prometheus -n monitoring

print_info "Waiting for Prometheus to restart..."
sleep 10

# Wait for pod to be ready
print_info "Waiting for Prometheus pod to be ready..."
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s

print_section "Fix Complete!"
echo ""
print_info "Prometheus has been updated with:"
print_info "  1. Fixed pod scraping configuration (proper IP:PORT format)"
print_info "  2. Fixed node scraping configuration (using API server proxy)"
print_info "  3. Updated RBAC permissions for node metrics"
echo ""
print_info "Check Prometheus targets in ~30 seconds:"
print_info "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
print_info "  Then visit: http://localhost:9090/targets"
echo ""
print_info "Pods and nodes should now show as 'UP' instead of 'DOWN'"

