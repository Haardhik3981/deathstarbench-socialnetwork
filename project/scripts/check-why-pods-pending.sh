#!/bin/bash

# Script to check why pods are stuck in Pending (can't be scheduled)

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

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo ""
print_step "=== Step 1: Check a Pending MongoDB Pod ==="
PENDING_MONGODB=$(kubectl get pods | grep "mongodb.*Pending" | head -1 | awk '{print $1}')
if [ -n "$PENDING_MONGODB" ] && [ "$PENDING_MONGODB" != "NAME" ]; then
    print_info "Checking pod: $PENDING_MONGODB"
    echo ""
    kubectl describe pod "$PENDING_MONGODB" | tail -50
else
    print_warn "No pending MongoDB pods found"
fi

echo ""
print_step "=== Step 2: Check Node Resources ==="
print_info "Checking if nodes have available CPU and memory..."
kubectl describe nodes | grep -A 8 "Allocated resources" | head -25

echo ""
print_step "=== Step 3: Check Node Capacity ==="
print_info "Total node resources:"
kubectl describe nodes | grep -E "Name:|cpu:|memory:" | head -20

echo ""
print_step "=== Summary ==="
print_info "Look for these messages in the pod description:"
echo "  - '0/X nodes are available: X Insufficient cpu'"
echo "  - '0/X nodes are available: X Insufficient memory'"
echo "  - 'pod has unbound immediate PersistentVolumeClaims' (not your case)"
echo ""
print_info "This will tell us exactly why pods can't be scheduled."

