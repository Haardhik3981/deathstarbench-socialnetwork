#!/bin/bash

# Deep cleanup - delete old ReplicaSets and their pods

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo ""
print_section "Deep Cleanup - Finding Root Cause"

echo ""
print_section "1. Check All ReplicaSets"
print_info "Looking for old ReplicaSets (these recreate duplicate pods)..."
kubectl get rs -o wide | head -30

echo ""
print_section "2. Check for Multiple ReplicaSets per Service"
print_info "Services with multiple ReplicaSets:"
kubectl get rs | awk '{print $1}' | cut -d'-' -f1-4 | sort | uniq -d

echo ""
print_section "3. Find Old ReplicaSets (0 replicas but still exist)"
print_info "Old ReplicaSets to delete:"
OLD_RS=$(kubectl get rs | awk '$2+$3+$4==0 && $1!="NAME" {print $1}')
if [ -n "$OLD_RS" ]; then
    for rs in $OLD_RS; do
        print_warn "  Found old RS: $rs (has 0 replicas but still exists)"
        echo "    Deleting..."
        kubectl delete rs "$rs" 2>/dev/null || true
    done
else
    print_info "  No old ReplicaSets found (with 0 replicas)"
fi

echo ""
print_section "4. Check All Deployments"
print_info "Current deployments:"
kubectl get deployment | head -25

echo ""
print_section "5. Find Duplicate Deployments"
print_info "Checking for multiple deployments with same service name..."
# This is harder to detect automatically, but let's see what we have

echo ""
print_section "6. Manual Cleanup - Delete Old ReplicaSets"
print_warn "You may need to manually delete old ReplicaSets."
print_info "Run this to see all ReplicaSets:"
echo "  kubectl get rs"
echo ""
print_info "Delete old ones (those with 0 desired replicas):"
echo "  kubectl delete rs <old-rs-name>"

