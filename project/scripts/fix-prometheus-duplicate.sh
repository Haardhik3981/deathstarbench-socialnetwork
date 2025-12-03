#!/bin/bash

# Fix duplicate Prometheus pods issue

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

print_section "Fixing Duplicate Prometheus Pods"

# Check current pod status
print_section "Current Prometheus Pod Status"
kubectl get pods -n monitoring -l app=prometheus

# Get all Prometheus pods
PROM_PODS=$(kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -z "$PROM_PODS" ]; then
    print_warn "No Prometheus pods found"
    exit 0
fi

# Count pods
POD_COUNT=$(echo "$PROM_PODS" | wc -l | tr -d ' ')

if [ "$POD_COUNT" -le 1 ]; then
    print_info "Only one Prometheus pod exists, no duplicates"
    exit 0
fi

print_warn "Found $POD_COUNT Prometheus pods - this is the problem!"
print_info "The PVC can only be mounted by one pod at a time"

# Scale down to 0 first
print_section "Step 1: Scaling Down Prometheus"
print_info "Scaling deployment to 0 replicas..."
kubectl scale deployment prometheus -n monitoring --replicas=0

print_info "Waiting 10 seconds for pods to terminate..."
sleep 10

# Delete any remaining pods (force cleanup)
print_section "Step 2: Force Deleting Any Remaining Pods"
REMAINING_PODS=$(kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -n "$REMAINING_PODS" ]; then
    echo "$REMAINING_PODS" | while read pod; do
        if [ -n "$pod" ] && [ "$pod" != "NAME" ]; then
            print_info "Force deleting pod: $pod"
            kubectl delete pod "$pod" -n monitoring --grace-period=0 --force 2>/dev/null || true
        fi
    done
    sleep 5
fi

# Scale back up
print_section "Step 3: Scaling Back Up to 1 Replica"
print_info "Scaling deployment to 1 replica..."
kubectl scale deployment prometheus -n monitoring --replicas=1

print_info "Waiting 30 seconds for pod to start..."
sleep 30

# Check final status
print_section "Final Status"
kubectl get pods -n monitoring -l app=prometheus

echo ""
print_info "The new pod should now be able to mount the PVC."
print_info "Check logs if issues persist:"
print_info "  kubectl logs -n monitoring -l app=prometheus --tail=50"

