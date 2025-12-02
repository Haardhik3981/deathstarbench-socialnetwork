#!/bin/bash

# Diagnostic script for monitoring pod crashes

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

print_section "Diagnosing Monitoring Pod Crashes"

# Get the most recent pod for each service
PROM_POD=$(kubectl get pods -n monitoring -l app=prometheus --sort-by='.metadata.creationTimestamp' --no-headers 2>/dev/null | tail -1 | awk '{print $1}')
GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana --sort-by='.metadata.creationTimestamp' --no-headers 2>/dev/null | tail -1 | awk '{print $1}')

# Prometheus diagnostics
if [ -n "$PROM_POD" ] && [ "$PROM_POD" != "NAME" ]; then
    print_section "Prometheus Pod: $PROM_POD"
    
    print_info "Pod status:"
    kubectl get pod "$PROM_POD" -n monitoring
    
    echo ""
    print_info "Pod events:"
    kubectl describe pod "$PROM_POD" -n monitoring | grep -A 30 "Events:" || true
    
    echo ""
    print_info "Container logs (last 50 lines):"
    kubectl logs "$PROM_POD" -n monitoring --tail=50 2>&1 || print_warn "Could not get logs"
    
    echo ""
    print_info "Previous container logs (from last crash):"
    kubectl logs "$PROM_POD" -n monitoring --previous --tail=50 2>&1 || print_warn "No previous logs"
else
    print_warn "No Prometheus pods found"
fi

echo ""
echo ""

# Grafana diagnostics
if [ -n "$GRAFANA_POD" ] && [ "$GRAFANA_POD" != "NAME" ]; then
    print_section "Grafana Pod: $GRAFANA_POD"
    
    print_info "Pod status:"
    kubectl get pod "$GRAFANA_POD" -n monitoring
    
    echo ""
    print_info "Pod events:"
    kubectl describe pod "$GRAFANA_POD" -n monitoring | grep -A 30 "Events:" || true
    
    echo ""
    print_info "Container logs (last 50 lines):"
    kubectl logs "$GRAFANA_POD" -n monitoring --tail=50 2>&1 || print_warn "Could not get logs"
    
    echo ""
    print_info "Previous container logs (from last crash):"
    kubectl logs "$GRAFANA_POD" -n monitoring --previous --tail=50 2>&1 || print_warn "No previous logs"
else
    print_warn "No Grafana pods found"
fi

echo ""
print_section "PVC Status"
kubectl get pvc -n monitoring

echo ""
print_section "Common Issues to Check"

print_info "1. If PVCs are not Bound:"
print_info "   - Check storage class: kubectl get storageclass"
print_info "   - Check PVC details: kubectl describe pvc <pvc-name> -n monitoring"

print_info "2. If pods are crashing with permission errors:"
print_info "   - Check RBAC: kubectl get clusterrolebinding prometheus"

print_info "3. If pods are crashing with file errors:"
print_info "   - Check ConfigMap mounts: kubectl describe pod <pod-name> -n monitoring | grep -A 10 Mounts"

print_info "4. If pods can't pull images:"
print_info "   - Check image pull secrets and network connectivity"

