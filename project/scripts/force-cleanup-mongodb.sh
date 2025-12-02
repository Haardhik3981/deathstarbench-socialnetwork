#!/bin/bash

# Force cleanup of duplicate MongoDB pods and ReplicaSets

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
print_section "Force Cleanup of Duplicate MongoDB ReplicaSets"

# The problem: We have duplicate ReplicaSets being created by the Deployments
# Solution: Delete the pods first, then the old ReplicaSets, then restart deployments

echo ""
print_section "Step 1: Identify Duplicate MongoDB Pods"
print_info "Finding all MongoDB pods..."

# Get all MongoDB pods
MONGODB_PODS=$(kubectl get pods -l component=database | grep mongodb | awk '{print $1}')

for pod in $MONGODB_PODS; do
    RS=$(kubectl get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "unknown")
    STATUS=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
    print_info "  Pod: $pod"
    print_info "    ReplicaSet: $RS"
    print_info "    Status: $STATUS"
done

echo ""
print_section "Step 2: Force Delete Pods from Old ReplicaSets"
print_info "Deleting pods from old/duplicate ReplicaSets..."

# Delete pods from the newer ReplicaSets (ones that were just created)
# We want to keep the old stable ones (6h19m old)

# social-graph-mongodb: Keep 844c5d745f (6h19m), delete pods from 69b966959c (new)
OLD_SG_PODS=$(kubectl get pods -l app=social-graph-mongodb --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$OLD_SG_PODS" ]; then
    for pod in $OLD_SG_PODS; do
        RS=$(kubectl get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
        if echo "$RS" | grep -q "69b966959c"; then
            print_info "  Deleting pod from old RS: $pod (RS: $RS)"
            kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
        fi
    done
fi

# url-shorten-mongodb: Keep 7b7658c4d5 (6h19m), delete pods from fc869fc99 (new)
OLD_US_PODS=$(kubectl get pods -l app=url-shorten-mongodb --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$OLD_US_PODS" ]; then
    for pod in $OLD_US_PODS; do
        RS=$(kubectl get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
        if echo "$RS" | grep -q "fc869fc99"; then
            print_info "  Deleting pod from old RS: $pod (RS: $RS)"
            kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
        fi
    done
fi

echo ""
print_section "Step 3: Delete the Newly Created ReplicaSets"
print_info "These ReplicaSets are duplicates and should not exist..."

# Delete the newly recreated ReplicaSets
NEW_RS=(
    "social-graph-mongodb-deployment-69b966959c"
    "url-shorten-mongodb-deployment-fc869fc99"
)

for rs in "${NEW_RS[@]}"; do
    if kubectl get rs "$rs" &>/dev/null; then
        print_info "  Deleting duplicate RS: $rs"
        kubectl delete rs "$rs" --grace-period=0 --force 2>/dev/null || print_warn "    Failed to delete"
    fi
done

echo ""
print_section "Step 4: Check MongoDB Deployments"
print_info "Checking if Deployments are creating duplicate ReplicaSets..."

# Check deployment history
for deploy in social-graph-mongodb-deployment url-shorten-mongodb-deployment; do
    if kubectl get deployment "$deploy" &>/dev/null; then
        print_info "  Deployment: $deploy"
        REPLICAS=$(kubectl get deployment "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "unknown")
        print_info "    Replicas: $REPLICAS"
        
        # Check how many ReplicaSets this deployment owns
        RS_COUNT=$(kubectl get rs -l app=${deploy%-deployment} | grep -v NAME | wc -l | tr -d ' ')
        print_info "    ReplicaSets: $RS_COUNT"
    fi
done

echo ""
print_section "Step 5: Restart MongoDB Deployments to Reset"
print_warn "If duplicates persist, we may need to restart the deployments"

# Wait a bit
sleep 5

echo ""
print_section "Final MongoDB Pod Count"
MONGODB_COUNT=$(kubectl get pods | grep mongodb | wc -l | tr -d ' ')
print_info "MongoDB pods: $MONGODB_COUNT (expected: 6)"

if [ "$MONGODB_COUNT" -gt 6 ]; then
    print_warn "Still have duplicates. Listing all MongoDB ReplicaSets:"
    kubectl get rs | grep mongodb
fi

