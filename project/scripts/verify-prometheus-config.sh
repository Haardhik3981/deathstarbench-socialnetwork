#!/bin/bash

# Verify Prometheus configuration and check for issues

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

print_section "Verifying Prometheus Configuration"

# Check pod status
print_section "Prometheus Pod Status"
kubectl get pods -n monitoring -l app=prometheus

echo ""
print_section "Prometheus Pod Logs (last 30 lines)"
PROM_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PROM_POD" ]; then
    print_info "Pod: $PROM_POD"
    kubectl logs -n monitoring "$PROM_POD" --tail=30 || print_warn "Could not get logs"
else
    print_warn "No Prometheus pod found"
fi

echo ""
print_section "Prometheus Configuration (from ConfigMap)"
kubectl get configmap prometheus-config -n monitoring -o jsonpath='{.data.prometheus\.yml}' | grep -A 30 "kubernetes-pods" || print_warn "Could not read config"

echo ""
print_section "Checking for Config Errors"
if kubectl get pods -n monitoring -l app=prometheus &>/dev/null; then
    PROM_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$PROM_POD" ]; then
        # Check if Prometheus is complaining about config
        kubectl logs -n monitoring "$PROM_POD" 2>&1 | grep -i "error\|invalid\|failed" | tail -10 || print_info "No obvious errors in logs"
    fi
fi

echo ""
print_section "Next Steps"
print_info "1. If Prometheus pod is not running, check: kubectl describe pod -n monitoring -l app=prometheus"
print_info "2. To reload config without restart: curl -X POST http://localhost:9090/-/reload (after port-forward)"
print_info "3. Or restart Prometheus: kubectl rollout restart deployment/prometheus -n monitoring"

