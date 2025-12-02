#!/bin/bash

# Final status check - verify all pods are running

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
print_section "Final Status Check - All Pods"

echo ""
print_section "1. Service Pods"
SERVICE_COUNT=$(kubectl get pods | grep service-deployment | grep Running | wc -l | tr -d ' ')
EXPECTED_SERVICES=11
print_info "Running services: $SERVICE_COUNT (expected: $EXPECTED_SERVICES)"
if [ "$SERVICE_COUNT" -eq "$EXPECTED_SERVICES" ]; then
    print_info "✓ All services running!"
else
    print_warn "Missing $((EXPECTED_SERVICES - SERVICE_COUNT)) service pod(s)"
    kubectl get pods | grep service-deployment | grep -v Running || true
fi

echo ""
print_section "2. MongoDB Pods"
MONGODB_COUNT=$(kubectl get pods | grep mongodb | grep Running | wc -l | tr -d ' ')
EXPECTED_MONGODB=6
print_info "Running MongoDB: $MONGODB_COUNT (expected: $EXPECTED_MONGODB)"
if [ "$MONGODB_COUNT" -eq "$EXPECTED_MONGODB" ]; then
    print_info "✓ All MongoDB pods running!"
else
    print_warn "Missing $((EXPECTED_MONGODB - MONGODB_COUNT)) MongoDB pod(s)"
    kubectl get pods | grep mongodb | grep -v Running || true
fi

echo ""
print_section "3. Cache Pods (Redis/Memcached)"
REDIS_COUNT=$(kubectl get pods | grep redis | grep Running | wc -l | tr -d ' ')
MEMCACHED_COUNT=$(kubectl get pods | grep memcached | grep Running | wc -l | tr -d ' ')
print_info "Running Redis: $REDIS_COUNT"
print_info "Running Memcached: $MEMCACHED_COUNT"

echo ""
print_section "4. Gateway Pods"
NGINX_THRIFT_COUNT=$(kubectl get pods -l app=nginx-thrift | grep Running | wc -l | tr -d ' ')
JAEGER_COUNT=$(kubectl get pods -l app=jaeger | grep Running | wc -l | tr -d ' ')
print_info "Running nginx-thrift: $NGINX_THRIFT_COUNT (expected: 1)"
print_info "Running jaeger: $JAEGER_COUNT (expected: 1)"

echo ""
print_section "5. Problem Pods"
CRASH_COUNT=$(kubectl get pods | grep CrashLoopBackOff | wc -l | tr -d ' ')
PENDING_COUNT=$(kubectl get pods | grep -E "Pending|ContainerCreating" | wc -l | tr -d ' ')
OOM_COUNT=$(kubectl get pods | grep -i "oom\|evicted" | wc -l | tr -d ' ')

print_info "CrashLoopBackOff: $CRASH_COUNT (expected: 0)"
print_info "Pending/ContainerCreating: $PENDING_COUNT (expected: 0)"
print_info "OOM/Evicted: $OOM_COUNT (expected: 0)"

if [ "$CRASH_COUNT" -gt 0 ]; then
    print_warn "Pods in CrashLoopBackOff:"
    kubectl get pods | grep CrashLoopBackOff
fi

if [ "$PENDING_COUNT" -gt 0 ]; then
    print_warn "Pods Pending/ContainerCreating:"
    kubectl get pods | grep -E "Pending|ContainerCreating"
fi

if [ "$OOM_COUNT" -gt 0 ]; then
    print_warn "Pods OOM/Evicted:"
    kubectl get pods | grep -i "oom\|evicted"
fi

echo ""
print_section "6. Overall Status"
TOTAL_RUNNING=$(kubectl get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
TOTAL_PODS=$(kubectl get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')

print_info "Total Running pods: $TOTAL_RUNNING"
print_info "Total pods: $TOTAL_PODS"

echo ""
if [ "$SERVICE_COUNT" -eq "$EXPECTED_SERVICES" ] && \
   [ "$MONGODB_COUNT" -eq "$EXPECTED_MONGODB" ] && \
   [ "$CRASH_COUNT" -eq 0 ] && \
   [ "$PENDING_COUNT" -eq 0 ] && \
   [ "$OOM_COUNT" -eq 0 ]; then
    print_info "✓✓✓ SUCCESS! All pods are running correctly! ✓✓✓"
    echo ""
    print_info "Memory Status:"
    echo "  - No OOM-killed pods"
    echo "  - All pods within memory limits"
    echo "  - Ready for testing!"
else
    print_warn "Some issues remain. Check the details above."
fi

echo ""
print_section "7. Quick Pod Summary"
kubectl get pods | head -30

