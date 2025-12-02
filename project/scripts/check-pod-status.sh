#!/bin/bash

# Check current pod status and resource usage

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
print_section "Current Pod Status Overview"

echo ""
print_section "1. Pod Status Summary"
kubectl get pods

echo ""
print_section "2. Pods by Status"
echo "Running:"
kubectl get pods --field-selector=status.phase=Running | grep -v NAME | wc -l | xargs echo
echo ""
echo "Pending:"
kubectl get pods --field-selector=status.phase=Pending
echo ""
echo "Failed/Error:"
kubectl get pods | grep -E "(Error|CrashLoopBackOff|OOMKilled|Evicted)" || echo "None found"

echo ""
print_section "3. Resource Usage - CPU"
kubectl describe nodes | grep -A 5 "Allocated resources" | head -20

echo ""
print_section "4. Resource Usage - Memory"
kubectl top nodes 2>/dev/null || echo "Metrics server not available"

echo ""
print_section "5. Memory Issues Check"
OOM_PODS=$(kubectl get pods | grep -E "OOMKilled|Evicted" || echo "")
if [ -n "$OOM_PODS" ]; then
    print_error "Found pods killed due to memory:"
    echo "$OOM_PODS"
else
    print_info "No OOM-killed pods found"
fi

echo ""
print_section "6. Detailed Status of Problem Pods"
PROBLEM_PODS=$(kubectl get pods | awk '$3!~/Running|Completed/ {print $1}' | tail -n +2)
if [ -n "$PROBLEM_PODS" ]; then
    for pod in $PROBLEM_PODS; do
        print_warn "Pod: $pod"
        kubectl describe pod "$pod" 2>/dev/null | grep -A 5 "State:\|Status:\|Events:" | head -10 || true
        echo ""
    done
else
    print_info "All pods are running!"
fi

echo ""
print_section "7. Node Capacity vs Requests"
kubectl describe nodes | grep -E "Allocatable:|Allocated resources:" -A 10 | head -30

