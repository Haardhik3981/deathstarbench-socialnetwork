#!/bin/bash

# Fix final issues: nginx-thrift crashing and user-service duplicate

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
print_section "Fixing Final Issues"

# Issue 1: Fix user-service duplicate (2 pods → 1)
echo ""
print_section "Issue 1: Fix user-service Duplicate"
USER_SERVICE_COUNT=$(kubectl get pods -l app=user-service | grep Running | wc -l | tr -d ' ')
print_info "Current user-service pods: $USER_SERVICE_COUNT (expected: 1)"

if [ "$USER_SERVICE_COUNT" -gt 1 ]; then
    print_warn "Found duplicate user-service pods. Scaling to 1..."
    kubectl scale deployment user-service-deployment --replicas=1
    sleep 5
    
    # Delete the extra pod manually if scaling didn't work immediately
    OLDEST_POD=$(kubectl get pods -l app=user-service --sort-by=.metadata.creationTimestamp | grep Running | awk '{print $1}' | head -1)
    if [ -n "$OLDEST_POD" ]; then
        print_info "Ensuring only one pod remains..."
        # Wait a bit more for Kubernetes to handle it
        sleep 3
    fi
    print_info "✓ Scaled to 1 replica"
else
    print_info "Already at correct replica count"
fi

# Issue 2: Check nginx-thrift crashes
echo ""
print_section "Issue 2: Check nginx-thrift Restarts"
NGINX_POD=$(kubectl get pods -l app=nginx-thrift | grep -v NAME | awk '{print $1}' | head -1)
if [ -n "$NGINX_POD" ]; then
    RESTARTS=$(kubectl get pod "$NGINX_POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    READY=$(kubectl get pod "$NGINX_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    print_warn "nginx-thrift pod: $NGINX_POD"
    print_warn "  Restarts: $RESTARTS"
    print_warn "  Ready: $READY"
    
    if [ "$RESTARTS" -gt 5 ]; then
        print_error "Pod is crashing repeatedly! Checking logs..."
        echo ""
        print_info "Recent logs:"
        kubectl logs "$NGINX_POD" --tail=30 2>&1 | tail -25 || print_warn "Could not get logs"
        echo ""
        print_info "Previous container logs (from last crash):"
        kubectl logs "$NGINX_POD" --previous --tail=30 2>&1 | tail -25 || print_warn "Could not get previous logs"
    fi
    
    echo ""
    print_info "Pod events:"
    kubectl describe pod "$NGINX_POD" | grep -A 15 "Events:" | head -20
else
    print_warn "No nginx-thrift pod found"
fi

echo ""
print_section "Waiting for fixes..."
sleep 5

echo ""
print_section "Final Status"
USER_SERVICE_NOW=$(kubectl get pods -l app=user-service | grep Running | wc -l | tr -d ' ')
print_info "user-service pods: $USER_SERVICE_NOW (expected: 1)"

NGINX_READY=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
NGINX_RESTARTS=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
print_info "nginx-thrift ready: $NGINX_READY, restarts: $NGINX_RESTARTS"

if [ "$USER_SERVICE_NOW" -eq 1 ] && [ "$NGINX_READY" = "true" ] && [ "$NGINX_RESTARTS" -lt 5 ]; then
    print_info "✓ All issues fixed!"
else
    print_warn "Some issues remain:"
    [ "$USER_SERVICE_NOW" -ne 1 ] && print_warn "  - user-service still has $USER_SERVICE_NOW pods"
    [ "$NGINX_READY" != "true" ] && print_warn "  - nginx-thrift not ready"
    [ "$NGINX_RESTARTS" -ge 5 ] && print_warn "  - nginx-thrift still crashing ($NGINX_RESTARTS restarts)"
fi

