#!/bin/bash

# Script to clean up old pods and check why new ones aren't starting

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

cd "$PROJECT_ROOT"

print_info "=== Step 1: Checking PVC Status ==="
kubectl get pvc

print_info "\n=== Step 2: Checking Storage Classes ==="
kubectl get storageclass

print_info "\n=== Step 3: Checking Node Resources ==="
kubectl top nodes 2>/dev/null || print_warn "kubectl top not available (metrics-server may not be installed)"

print_info "\n=== Step 4: Checking a Pending Service Pod ==="
PENDING_SERVICE=$(kubectl get pods | grep -E "service-deployment.*Pending" | head -1 | awk '{print $1}')
if [ -n "$PENDING_SERVICE" ]; then
    print_info "Checking pending pod: $PENDING_SERVICE"
    kubectl describe pod "$PENDING_SERVICE" | grep -A 20 "Events:" || kubectl describe pod "$PENDING_SERVICE" | tail -30
else
    print_info "No pending service pods found"
fi

print_info "\n=== Step 5: Checking New Pod Logs (to verify config fix worked) ==="
# Find newest user-service pod
NEW_USER_POD=$(kubectl get pods -l app=user-service --sort-by=.metadata.creationTimestamp | tail -1 | awk '{print $1}')
if [ -n "$NEW_USER_POD" ] && [ "$NEW_USER_POD" != "NAME" ]; then
    print_info "Checking logs for newest user-service pod: $NEW_USER_POD"
    kubectl logs "$NEW_USER_POD" --tail=30 2>&1 || print_warn "Could not get logs (pod may not be running yet)"
else
    print_warn "No user-service pods found"
fi

print_info "\n=== Step 6: Checking a Pending Database Pod ==="
PENDING_DB=$(kubectl get pods | grep -E "mongodb.*Pending|redis.*Pending" | head -1 | awk '{print $1}')
if [ -n "$PENDING_DB" ]; then
    print_info "Checking pending database pod: $PENDING_DB"
    kubectl describe pod "$PENDING_DB" | grep -A 20 "Events:" || kubectl describe pod "$PENDING_DB" | tail -30
else
    print_info "No pending database pods found"
fi

print_info "\n=== Step 7: Summary ==="
echo ""
print_info "Current pod status:"
kubectl get pods | grep -E "NAME|Pending|Error|CrashLoopBackOff" | head -15

echo ""
print_warn "Next steps based on findings:"
echo "  - If PVCs are pending: Check storage class and node storage"
echo "  - If pods are pending due to resources: Reduce requests or scale cluster"
echo "  - If new pods still crash: Check logs for errors"
echo "  - If old pods still exist: Delete them to force new deployments"

