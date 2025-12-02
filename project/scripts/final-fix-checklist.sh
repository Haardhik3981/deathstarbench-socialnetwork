#!/bin/bash

# Final checklist to get everything working

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

CLUSTER_NAME="${GKE_CLUSTER:-social-network-cluster}"
ZONE="${GKE_ZONE:-us-central1-a}"

echo ""
print_step "=== Status Check ==="

# Count running services
RUNNING_SERVICES=$(kubectl get pods | grep -E "service-deployment.*Running" | wc -l | tr -d ' ')
print_success "Services Running: $RUNNING_SERVICES"

# Count pending pods
PENDING_COUNT=$(kubectl get pods | grep -c Pending || echo "0")
if [ "$PENDING_COUNT" -gt 0 ]; then
    print_warn "Pods Pending: $PENDING_COUNT (likely CPU constraint)"
fi

# Count crashing old pods
OLD_CRASHING=$(kubectl get pods | grep CrashLoopBackOff | grep -E "4h|5h" | wc -l | tr -d ' ' || echo "0")
if [ "$OLD_CRASHING" -gt 0 ]; then
    print_warn "Old Crashing Pods: $OLD_CRASHING (can be cleaned up)"
fi

echo ""
print_step "=== CPU Check ==="
print_info "Checking node CPU usage..."
CPU_LINE=$(kubectl describe nodes | grep -A 3 "Allocated resources" | grep cpu || echo "")
if [ -n "$CPU_LINE" ]; then
    echo "$CPU_LINE"
    CPU_PCT=$(echo "$CPU_LINE" | grep -oE '[0-9]+%' | head -1 | sed 's/%//')
    if [ -n "$CPU_PCT" ] && [ "$CPU_PCT" -gt 90 ]; then
        print_warn "CPU usage is high ($CPU_PCT%). Should scale up cluster."
    fi
else
    print_info "Could not determine CPU usage"
fi

echo ""
print_step "=== Recommendations ==="

if [ "$PENDING_COUNT" -gt 10 ]; then
    print_warn "Many pods still pending. Recommendation:"
    echo "  1. Scale up cluster: gcloud container clusters resize $CLUSTER_NAME --num-nodes=2 --zone=$ZONE"
    echo "  2. Wait 2-5 minutes for new node"
    echo "  3. Watch pods: kubectl get pods -w"
fi

if [ "$OLD_CRASHING" -gt 0 ]; then
    print_warn "Old crashing pods can be cleaned up:"
    echo "  kubectl delete pod \$(kubectl get pods | grep CrashLoopBackOff | awk '{print \$1}')"
fi

echo ""
print_step "=== Services Status ==="
print_info "Running services:"
kubectl get pods | grep -E "service-deployment.*Running" | awk '{print "  ✓ " $1}' || echo "  (none yet)"

echo ""
print_info "Check nginx-thrift logs:"
echo "  kubectl logs -l app=nginx-thrift --tail=50"

