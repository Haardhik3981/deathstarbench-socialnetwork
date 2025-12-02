#!/bin/bash

# Final cleanup to fix remaining duplicates

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
print_section "Final Cleanup - Fix Remaining Duplicates"

# Step 1: Scale down user-service to 1 replica
echo ""
print_section "Step 1: Fix user-service (currently has 2 replicas)"
CURRENT_REPLICAS=$(kubectl get deployment user-service-deployment -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "unknown")
print_info "Current replicas: $CURRENT_REPLICAS"
if [ "$CURRENT_REPLICAS" != "1" ]; then
    print_info "Scaling user-service-deployment to 1 replica..."
    kubectl scale deployment user-service-deployment --replicas=1
    print_info "✓ Scaled down"
else
    print_info "✓ Already at 1 replica"
fi

# Step 2: Delete old MongoDB ReplicaSets
echo ""
print_section "Step 2: Delete Old MongoDB ReplicaSets"
print_info "Deleting old MongoDB ReplicaSets (keep only newest ones)..."

# Old MongoDB ReplicaSets to delete (ones with 0 ready pods or older ones)
OLD_MONGODB_RS=(
    "social-graph-mongodb-deployment-69b966959c"  # 0 ready, keep 844c5d745f
    "url-shorten-mongodb-deployment-fc869fc99"     # 0 ready, keep 7b7658c4d5
    "user-mongodb-deployment-6475c8b6c9"           # 0 ready, keep 7b649fbd77
    "user-timeline-mongodb-deployment-69c6c64fb7"  # 0 ready - check if there's a newer one
)

for rs in "${OLD_MONGODB_RS[@]}"; do
    if kubectl get rs "$rs" &>/dev/null; then
        print_info "  Deleting old RS: $rs"
        kubectl delete rs "$rs" 2>/dev/null || print_warn "    Failed to delete (may already be gone)"
    else
        print_info "  RS $rs already deleted"
    fi
done

# Step 3: Delete old nginx-thrift ReplicaSets (keep newest)
echo ""
print_section "Step 3: Delete Old nginx-thrift ReplicaSets"
print_info "Finding nginx-thrift ReplicaSets..."
NGINX_RS=$(kubectl get rs | grep nginx-thrift | awk '{print $1}')
if [ -n "$NGINX_RS" ]; then
    # Sort by age, delete older ones
    OLDEST_NGINX=$(echo "$NGINX_RS" | head -1)
    if [ $(echo "$NGINX_RS" | wc -l) -gt 1 ]; then
        for rs in $NGINX_RS; do
            if [ "$rs" != "$OLDEST_NGINX" ]; then
                print_info "  Deleting old nginx-thrift RS: $rs"
                kubectl delete rs "$rs" 2>/dev/null || print_warn "    Failed"
            fi
        done
    fi
fi

# Step 4: Delete old nginx deployment (we don't need it, only nginx-thrift)
echo ""
print_section "Step 4: Clean Up Old nginx Deployment"
if kubectl get deployment nginx-deployment &>/dev/null; then
    print_warn "Old nginx-deployment exists (we use nginx-thrift now)"
    print_info "Should we delete it? (It's not needed if nginx-thrift works)"
    # Just note it for now, don't auto-delete
fi

# Step 5: Wait and check
echo ""
print_section "Step 5: Waiting for cleanup to complete..."
sleep 10

echo ""
print_section "Final Status Check"
print_info "Service pods: $(kubectl get pods | grep service-deployment | wc -l | tr -d ' ') (expected: 11)"
print_info "MongoDB pods: $(kubectl get pods | grep mongodb | wc -l | tr -d ' ') (expected: 6)"
print_info "user-service RS replicas:"
kubectl get rs | grep user-service-deployment || true

echo ""
print_info "✓ Cleanup complete!"
print_info "If counts are still wrong, check for remaining old ReplicaSets:"
echo "  kubectl get rs | grep -E '(mongodb|nginx-thrift|user-service)'"

