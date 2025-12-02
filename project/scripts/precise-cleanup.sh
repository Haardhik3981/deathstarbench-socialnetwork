#!/bin/bash

# Precise cleanup based on actual ReplicaSet analysis

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
print_section "Precise Cleanup Based on ReplicaSet Analysis"

# Fix 1: Scale user-service from 2 to 1 replica
echo ""
print_section "Fix 1: Scale user-service-deployment to 1 replica"
CURRENT_REPLICAS=$(kubectl get deployment user-service-deployment -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
print_info "Current replicas: $CURRENT_REPLICAS"
if [ "$CURRENT_REPLICAS" = "2" ]; then
    print_info "Scaling down to 1..."
    kubectl scale deployment user-service-deployment --replicas=1
    sleep 3
    print_info "✓ Scaled to 1"
else
    print_info "Already at correct replica count"
fi

# Fix 2: Delete old MongoDB ReplicaSets (ones with 0 ready pods)
echo ""
print_section "Fix 2: Delete Old MongoDB ReplicaSets"
print_info "Deleting MongoDB ReplicaSets with 0 ready pods..."

# These are the old ones from the kubectl get rs output
OLD_MONGODB_RS=(
    "social-graph-mongodb-deployment-69b966959c"   # 0 ready - old, keep 844c5d745f
    "url-shorten-mongodb-deployment-fc869fc99"     # 0 ready - old, keep 7b7658c4d5  
    "user-mongodb-deployment-6475c8b6c9"           # 0 ready - old, keep 7b649fbd77
)

for rs in "${OLD_MONGODB_RS[@]}"; do
    if kubectl get rs "$rs" &>/dev/null; then
        READY=$(kubectl get rs "$rs" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        print_info "  Deleting RS: $rs (ready: $READY)"
        kubectl delete rs "$rs" --grace-period=0 2>/dev/null || print_warn "    Already deleted or failed"
    fi
done

# Check user-timeline-mongodb - it shows 0 ready, but we need it
echo ""
print_info "Checking user-timeline-mongodb..."
if kubectl get rs user-timeline-mongodb-deployment-69c6c64fb7 &>/dev/null; then
    READY=$(kubectl get rs user-timeline-mongodb-deployment-69c6c64fb7 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$READY" = "0" ]; then
        print_warn "  user-timeline-mongodb has 0 ready pods - checking if pod exists..."
        POD=$(kubectl get pods -l app=user-timeline-mongodb 2>/dev/null | grep -v NAME | head -1 | awk '{print $1}' || echo "")
        if [ -n "$POD" ]; then
            print_info "  Pod exists: $POD - RS will be kept (pod may be starting)"
        fi
    fi
fi

# Fix 3: Delete older nginx-thrift ReplicaSet (keep newest)
echo ""
print_section "Fix 3: Clean Up Duplicate nginx-thrift ReplicaSets"
NGINX_RS_LIST=$(kubectl get rs | grep nginx-thrift | awk '{print $1}')
NGINX_COUNT=$(echo "$NGINX_RS_LIST" | grep -v "^$" | wc -l | tr -d ' ')

if [ "$NGINX_COUNT" -gt 1 ]; then
    print_info "Found $NGINX_COUNT nginx-thrift ReplicaSets"
    # Delete the older one (30m age vs 7m age)
    OLDER_NGINX="nginx-thrift-deployment-5f8c6d48bd"  # 30m old
    if kubectl get rs "$OLDER_NGINX" &>/dev/null; then
        print_info "  Deleting older RS: $OLDER_NGINX (30m old)"
        kubectl delete rs "$OLDER_NGINX" --grace-period=0 2>/dev/null || print_warn "    Failed"
    fi
else
    print_info "Only one nginx-thrift ReplicaSet found"
fi

# Wait for cleanup
echo ""
print_section "Waiting for cleanup to stabilize..."
sleep 10

# Final status
echo ""
print_section "Final Status"
SERVICE_COUNT=$(kubectl get pods | grep service-deployment | wc -l | tr -d ' ')
MONGODB_COUNT=$(kubectl get pods | grep mongodb | wc -l | tr -d ' ')
USER_RS_REPLICAS=$(kubectl get rs user-service-deployment-54787dcf4b -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "N/A")

print_info "Service pods: $SERVICE_COUNT (expected: 11)"
print_info "MongoDB pods: $MONGODB_COUNT (expected: 6)"
print_info "user-service RS desired replicas: $USER_RS_REPLICAS"

if [ "$SERVICE_COUNT" = "11" ] && [ "$MONGODB_COUNT" = "6" ]; then
    echo ""
    print_info "✓ SUCCESS! Pod counts are correct!"
else
    echo ""
    print_warn "Still have duplicates. Checking remaining ReplicaSets..."
    echo ""
    kubectl get rs | grep -E "(service|mongodb)" | head -15
fi

