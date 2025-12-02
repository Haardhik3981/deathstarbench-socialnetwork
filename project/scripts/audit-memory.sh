#!/bin/bash

# Comprehensive memory audit for all pods

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
print_section "Comprehensive Memory Audit"

echo ""
print_section "1. Pod Status Overview"
kubectl get pods -o wide

echo ""
print_section "2. Memory-Related Failures"
OOM_PODS=$(kubectl get pods | grep -iE "oom|evicted" || echo "")
if [ -n "$OOM_PODS" ]; then
    print_error "Found pods killed due to memory issues:"
    echo "$OOM_PODS"
    for pod in $(echo "$OOM_PODS" | awk 'NR>1 {print $1}'); do
        print_error "Details for $pod:"
        kubectl describe pod "$pod" | grep -A 5 "Last State\|Reason:" | head -10
        echo ""
    done
else
    print_info "✓ No OOM-killed or evicted pods found"
fi

echo ""
print_section "3. Node Memory Capacity"
kubectl describe nodes | grep -E "Allocatable:|Allocated resources:" -A 8 | grep -i memory

echo ""
print_section "4. CrashLoopBackOff Pods (may be memory-related)"
CRASH_PODS=$(kubectl get pods | grep CrashLoopBackOff || echo "")
if [ -n "$CRASH_PODS" ]; then
    print_warn "Pods in CrashLoopBackOff:"
    echo "$CRASH_PODS"
    for pod in $(echo "$CRASH_PODS" | awk '{print $1}'); do
        if [ "$pod" != "NAME" ]; then
            print_warn "Checking $pod..."
            kubectl logs "$pod" --tail=20 2>&1 | tail -10 || kubectl logs "$pod" --previous --tail=20 2>&1 | tail -10 || echo "  No logs available"
            echo ""
        fi
    done
else
    print_info "✓ No CrashLoopBackOff pods"
fi

echo ""
print_section "5. ContainerCreating Pods (may be waiting for resources)"
PENDING_PODS=$(kubectl get pods | grep ContainerCreating || echo "")
if [ -n "$PENDING_PODS" ]; then
    print_warn "Pods in ContainerCreating state:"
    echo "$PENDING_PODS"
    for pod in $(echo "$PENDING_PODS" | awk '{print $1}'); do
        if [ "$pod" != "NAME" ]; then
            print_warn "Events for $pod:"
            kubectl describe pod "$pod" | grep -A 10 "Events:" | head -15
            echo ""
        fi
    done
else
    print_info "✓ No pods stuck in ContainerCreating"
fi

echo ""
print_section "6. Summary - Pod Counts by Status"
RUNNING=$(kubectl get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
PENDING=$(kubectl get pods --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
FAILED=$(kubectl get pods --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l | tr -d ' ')

print_info "Running: $RUNNING"
print_info "Pending: $PENDING"
print_info "Failed: $FAILED"

TOTAL=$((RUNNING + PENDING + FAILED))
EXPECTED=28  # 11 services + 6 MongoDB + 3 Redis + 4 Memcached + 1 nginx-thrift + 1 jaeger + 1 nginx (old) = 28
print_info "Total: $TOTAL (expected: ~$EXPECTED)"

echo ""
print_section "7. Next Steps"
if [ "$FAILED" -gt 0 ] || [ "$PENDING" -gt 3 ]; then
    print_warn "There are issues to address. Check the details above."
    echo "  - Review OOM/evicted pods"
    echo "  - Check CrashLoopBackOff pods"
    echo "  - Investigate ContainerCreating pods"
else
    print_info "✓ Most pods appear healthy. Monitor memory usage if issues arise."
fi

