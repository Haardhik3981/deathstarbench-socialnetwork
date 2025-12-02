#!/bin/bash

# Clean up ALL duplicate pods from old deployments

set -e

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

echo ""
print_info "=== Cleaning Up All Duplicate Pods ==="
echo ""

# Get current running pods (newest ones)
print_info "Finding pods to keep (newest from each deployment)..."
echo ""

# For each deployment type, keep the newest pod, delete old ones
print_info "Deleting duplicate user-service pods..."
USER_PODS=$(kubectl get pods | grep "user-service-deployment" | awk '{print $1}')
USER_NEWEST=$(echo "$USER_PODS" | tail -1)
for pod in $USER_PODS; do
    if [ "$pod" != "$USER_NEWEST" ]; then
        print_info "  Deleting old pod: $pod"
        kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
    else
        print_info "  Keeping: $pod"
    fi
done

echo ""
print_info "Deleting duplicate MongoDB pods..."
# Get all mongodb pods, keep newest of each type
MONGODB_TYPES=$(kubectl get pods | grep mongodb | awk '{print $1}' | cut -d'-' -f1-3 | sort -u)
for type in $MONGODB_TYPES; do
    TYPE_PODS=$(kubectl get pods | grep "^${type}" | awk '{print $1}')
    TYPE_NEWEST=$(echo "$TYPE_PODS" | tail -1)
    for pod in $TYPE_PODS; do
        if [ "$pod" != "$TYPE_NEWEST" ]; then
            print_info "  Deleting old pod: $pod"
            kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
        else
            print_info "  Keeping: $pod"
        fi
    done
done

echo ""
print_info "Deleting old ReplicaSets (these create duplicate pods)..."
print_warn "Finding old ReplicaSets..."
OLD_RS=$(kubectl get rs | grep -E "0.*user-service|0.*mongodb" | awk '{print $1}')
for rs in $OLD_RS; do
    print_info "  Deleting old ReplicaSet: $rs"
    kubectl delete rs "$rs" 2>/dev/null || true
done

echo ""
print_info "Waiting 10 seconds for cleanup..."
sleep 10

echo ""
print_info "=== Checking Remaining Pods ==="
echo "Services: $(kubectl get pods | grep service-deployment | wc -l | tr -d ' ') (expected: 11)"
echo "MongoDB: $(kubectl get pods | grep mongodb | wc -l | tr -d ' ') (expected: 6)"
echo "Redis: $(kubectl get pods | grep redis | wc -l | tr -d ' ') (expected: 3)"
echo "Memcached: $(kubectl get pods | grep memcached | wc -l | tr -d ' ') (expected: 4)"

echo ""
print_info "✓ Cleanup complete!"
print_info "Check CPU usage: kubectl describe nodes | grep -A 5 'Allocated resources'"
print_info "nginx-thrift pods should be able to schedule now!"

