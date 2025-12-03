#!/bin/bash

# Complete fix for Prometheus: cleanup and restart cleanly

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

print_section "Complete Prometheus Fix"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Step 1: Scale down
print_section "Step 1: Stopping All Prometheus Pods"
kubectl scale deployment prometheus -n monitoring --replicas=0 2>/dev/null || true
sleep 10

# Step 2: Delete all pods
print_section "Step 2: Deleting All Prometheus Pods"
kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | awk '{print $1}' | while read pod; do
    if [ -n "$pod" ] && [ "$pod" != "NAME" ]; then
        print_info "Deleting pod: $pod"
        kubectl delete pod "$pod" -n monitoring --grace-period=0 --force 2>/dev/null || true
    fi
done
sleep 5

# Step 3: Delete all ReplicaSets
print_section "Step 3: Deleting All ReplicaSets"
kubectl get rs -n monitoring -l app=prometheus --no-headers 2>/dev/null | awk '{print $1}' | while read rs; do
    if [ -n "$rs" ] && [ "$rs" != "NAME" ]; then
        print_info "Deleting ReplicaSet: $rs"
        kubectl delete rs "$rs" -n monitoring --grace-period=0 --force 2>/dev/null || true
    fi
done
sleep 5

# Step 4: Apply fixed config
print_section "Step 4: Applying Fixed Configuration"
print_info "Applying updated prometheus-configmap.yaml (with fixed regex)..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml"

# Step 5: Apply deployment (ensure it's up to date)
kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-deployment.yaml"

# Step 6: Scale up
print_section "Step 5: Starting Fresh Prometheus Pod"
kubectl scale deployment prometheus -n monitoring --replicas=1

print_info "Waiting 40 seconds for pod to start..."
sleep 40

# Step 7: Check status
print_section "Step 6: Status Check"
kubectl get pods -n monitoring -l app=prometheus

PROM_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PROM_POD" ]; then
    echo ""
    print_info "Checking pod logs..."
    kubectl logs -n monitoring "$PROM_POD" --tail=30 2>&1 | tail -20 || print_warn "Could not get logs"
    
    echo ""
    POD_READY=$(kubectl get pod "$PROM_POD" -n monitoring -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    if [ "$POD_READY" = "true" ]; then
        print_info "✓ Prometheus pod is ready!"
    else
        print_warn "Pod is not ready yet. Check with: kubectl describe pod $PROM_POD -n monitoring"
    fi
fi

echo ""
print_section "Done!"
print_info "If pod is running, access Prometheus:"
print_info "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
print_info "  Then visit: http://localhost:9090/targets"

