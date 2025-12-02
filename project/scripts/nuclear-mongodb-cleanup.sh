#!/bin/bash

# Nuclear option: Force delete duplicate MongoDB ReplicaSets and pods

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
print_section "Nuclear MongoDB Cleanup - Fix Duplicate ReplicaSets"

echo ""
print_section "Current State"
kubectl get rs | grep mongodb

echo ""
print_section "Step 1: Delete All Pods from Duplicate ReplicaSets"

# social-graph-mongodb: Keep 844c5d745f, delete 69b966959c
print_info "Deleting pods from: social-graph-mongodb-deployment-69b966959c"
PODS=$(kubectl get pods -l app=social-graph-mongodb -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
for pod in $PODS; do
    RS=$(kubectl get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
    if echo "$RS" | grep -q "69b966959c"; then
        print_info "  Deleting pod: $pod (from RS: $RS)"
        kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
    fi
done

# url-shorten-mongodb: Keep 7b7658c4d5, delete fc869fc99
print_info "Deleting pods from: url-shorten-mongodb-deployment-fc869fc99"
PODS=$(kubectl get pods -l app=url-shorten-mongodb -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
for pod in $PODS; do
    RS=$(kubectl get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
    if echo "$RS" | grep -q "fc869fc99"; then
        print_info "  Deleting pod: $pod (from RS: $RS)"
        kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
    fi
done

sleep 3

echo ""
print_section "Step 2: Scale Deployments to 0 Then Back to 1"
print_warn "This will temporarily stop MongoDB, but ensures clean ReplicaSets"

# Get list of MongoDB deployments
MONGODB_DEPLOYMENTS=(
    "social-graph-mongodb-deployment"
    "url-shorten-mongodb-deployment"
)

for deploy in "${MONGODB_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deploy" &>/dev/null; then
        print_info "Processing: $deploy"
        
        # Scale to 0
        print_info "  Scaling to 0..."
        kubectl scale deployment "$deploy" --replicas=0
        sleep 2
        
        # Delete old ReplicaSets while scaled down
        OLD_RS=$(kubectl get rs | grep "^${deploy}" | grep -v "$(kubectl get deployment "$deploy" -o jsonpath='{.status.observedGeneration}')" | awk '{print $1}' || echo "")
        if [ -n "$OLD_RS" ]; then
            for rs in $OLD_RS; do
                print_info "    Deleting old RS: $rs"
                kubectl delete rs "$rs" --grace-period=0 --force 2>/dev/null || true
            done
        fi
        
        # Wait a bit
        sleep 2
        
        # Scale back to 1
        print_info "  Scaling back to 1..."
        kubectl scale deployment "$deploy" --replicas=1
        sleep 2
    fi
done

echo ""
print_section "Step 3: Alternative - Just Delete the Duplicate ReplicaSets Directly"
print_info "Trying direct deletion of duplicate ReplicaSets..."

# Force delete the duplicate ReplicaSets
DUPLICATE_RS=(
    "social-graph-mongodb-deployment-69b966959c"
    "url-shorten-mongodb-deployment-fc869fc99"
)

for rs in "${DUPLICATE_RS[@]}"; do
    if kubectl get rs "$rs" &>/dev/null; then
        print_info "Force deleting RS: $rs"
        # First, delete any pods it owns
        kubectl delete pods -l app=$(echo "$rs" | sed 's/-deployment-.*//') --field-selector=status.phase!=Running 2>/dev/null || true
        # Then delete the RS
        kubectl delete rs "$rs" --grace-period=0 --force 2>/dev/null || print_warn "  Failed to delete"
    fi
done

sleep 5

echo ""
print_section "Final Check"
print_info "MongoDB ReplicaSets:"
kubectl get rs | grep mongodb

echo ""
MONGODB_COUNT=$(kubectl get pods | grep mongodb | wc -l | tr -d ' ')
print_info "MongoDB pods: $MONGODB_COUNT (expected: 6)"

if [ "$MONGODB_COUNT" = "6" ]; then
    print_info "✓ SUCCESS! MongoDB pod count is correct!"
else
    print_warn "Still have $MONGODB_COUNT MongoDB pods. Listing all:"
    kubectl get pods | grep mongodb
fi

