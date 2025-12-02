#!/bin/bash

# Check memory usage and limits across all pods

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
print_section "Memory Usage Analysis"

echo ""
print_section "1. Node Memory Capacity and Usage"
kubectl describe nodes | grep -E "Allocatable:|Allocated resources:" -A 10 | grep -E "memory|Memory" | head -20

echo ""
print_section "2. Pod Memory Requests and Limits"
echo "Pods with memory configuration:"
kubectl get pods -o json | jq -r '.items[] | "\(.metadata.name)|Requests: \(.spec.containers[0].resources.requests.memory // "none")|Limits: \(.spec.containers[0].resources.limits.memory // "none")"' 2>/dev/null | column -t -s '|' || echo "jq not available, showing raw data..."

echo ""
print_section "3. Memory-Related Pod Issues"
OOM_PODS=$(kubectl get pods | grep -i "oom\|evicted" || echo "")
if [ -n "$OOM_PODS" ]; then
    print_warn "Found memory-related issues:"
    echo "$OOM_PODS"
    for pod in $(echo "$OOM_PODS" | awk '{print $1}'); do
        if [ "$pod" != "NAME" ]; then
            echo ""
            print_warn "Details for $pod:"
            kubectl describe pod "$pod" | grep -A 10 "Last State\|Events:" | head -15
        fi
    done
else
    print_info "No OOM-killed or evicted pods found"
fi

echo ""
print_section "4. Current Pod Status"
kubectl get pods -o wide

echo ""
print_section "5. Summary of Memory Requests"
echo "Calculating total memory requests..."
kubectl get pods -o json | jq '[.items[].spec.containers[0].resources.requests.memory // "0Mi"] | map(select(. != "none") | gsub("Mi"; "") | tonumber) | add' 2>/dev/null || echo "Cannot calculate automatically"

echo ""
print_section "6. Problem Pods Detail"
PROBLEM_PODS=$(kubectl get pods | awk '$3!~/Running|Completed/ && $1!="NAME" {print $1}')
if [ -n "$PROBLEM_PODS" ]; then
    for pod in $PROBLEM_PODS; do
        print_warn "Checking pod: $pod"
        kubectl describe pod "$pod" | grep -E "State:|Last State:|Reason:|Message:|OOMKilled|Memory|Limit" | head -10 || true
        echo ""
    done
else
    print_info "All pods appear to be running normally"
fi

