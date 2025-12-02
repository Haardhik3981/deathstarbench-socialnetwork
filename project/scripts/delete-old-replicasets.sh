#!/bin/bash

# Delete old ReplicaSets that are creating duplicate pods

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo ""
print_info "=== Finding and Deleting Old ReplicaSets ==="
echo ""

# Get all ReplicaSets and show which ones have 0 desired replicas
print_info "All ReplicaSets:"
kubectl get rs

echo ""
print_info "Finding ReplicaSets with 0 desired replicas (old ones)..."
OLD_RS=$(kubectl get rs -o json | jq -r '.items[] | select(.spec.replicas == 0) | .metadata.name' 2>/dev/null)

if [ -z "$OLD_RS" ]; then
    # Alternative method if jq not available
    OLD_RS=$(kubectl get rs | awk 'NR>1 && ($2+$3+$4==0) {print $1}')
fi

if [ -n "$OLD_RS" ]; then
    echo ""
    print_info "Deleting old ReplicaSets:"
    for rs in $OLD_RS; do
        print_info "  Deleting: $rs"
        kubectl delete rs "$rs" 2>/dev/null || print_warn "    Failed (may already be deleted)"
    done
else
    print_info "No old ReplicaSets found with 0 replicas"
fi

echo ""
print_info "=== Looking for ReplicaSets with Multiple Pods ==="
# Check for RS that have more pods than they should
MULTI_RS=$(kubectl get rs -o json | jq -r '.items[] | select(.spec.replicas == 1 and .status.replicas > 1) | .metadata.name' 2>/dev/null)

if [ -n "$MULTI_RS" ]; then
    print_warn "Found ReplicaSets with more pods than desired:"
    for rs in $MULTI_RS; do
        print_warn "  $rs"
        # Scale it down
        kubectl scale rs "$rs" --replicas=1
    done
fi

echo ""
print_info "=== Checking Current Pod Counts After Cleanup ==="
sleep 5
echo "Services: $(kubectl get pods | grep service-deployment | wc -l | tr -d ' ') (expected: 11)"
echo "MongoDB: $(kubectl get pods | grep mongodb | wc -l | tr -d ' ') (expected: 6)"
echo ""
print_info "If counts are still high, check for multiple deployments of same service"

