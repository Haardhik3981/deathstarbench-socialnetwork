#!/bin/bash

# Fix the current issues found in the audit

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
print_section "Fixing Current Issues"

# Issue 1: Delete old nginx deployment (not needed, we use nginx-thrift)
echo ""
print_section "Issue 1: Delete Old nginx Deployment"
print_info "The old nginx-deployment is not needed (we use nginx-thrift)"
if kubectl get deployment nginx-deployment &>/dev/null; then
    print_info "Deleting old nginx-deployment..."
    kubectl delete deployment nginx-deployment
    print_info "✓ Deleted"
else
    print_info "Already deleted"
fi

# Issue 2: Fix user-service duplicate (should only be 1 pod)
echo ""
print_section "Issue 2: Fix user-service Duplicate"
print_info "Checking user-service pods..."
USER_SERVICE_PODS=$(kubectl get pods -l app=user-service | grep Running | wc -l | tr -d ' ')
if [ "$USER_SERVICE_PODS" -gt 1 ]; then
    print_warn "Found $USER_SERVICE_PODS user-service pods (should be 1)"
    print_info "Scaling user-service-deployment to 1 replica..."
    kubectl scale deployment user-service-deployment --replicas=1
    sleep 5
    print_info "✓ Scaled to 1"
else
    print_info "Already at correct replica count"
fi

# Issue 3: Fix user-timeline-mongodb (needs repair - corrupted database)
echo ""
print_section "Issue 3: Fix user-timeline-mongodb (Corrupted Database)"
print_warn "MongoDB needs repair due to missing featureCompatibilityVersion document"
print_info "Option 1: Delete and recreate (will lose data)"
print_info "Option 2: Run repair command"
print_info ""
print_info "For now, deleting the pod to let it recreate (clean start)..."
kubectl delete pod -l app=user-timeline-mongodb --grace-period=0 --force 2>/dev/null || true
print_info "Pod deleted, will recreate automatically"
print_warn "If it still crashes, we may need to delete the PVC and recreate"

# Issue 4: Check nginx-thrift logs
echo ""
print_section "Issue 4: Check nginx-thrift Status"
print_info "Checking nginx-thrift logs..."
NGINX_POD=$(kubectl get pods -l app=nginx-thrift | grep -v NAME | awk '{print $1}' | head -1)
if [ -n "$NGINX_POD" ]; then
    print_info "nginx-thrift pod: $NGINX_POD"
    print_info "Recent logs:"
    kubectl logs "$NGINX_POD" --tail=20 2>&1 | tail -15 || print_warn "Could not get logs"
else
    print_warn "No nginx-thrift pod found"
fi

echo ""
print_section "Waiting for fixes to take effect..."
sleep 10

echo ""
print_section "Current Status"
print_info "Checking pod counts:"
SERVICE_COUNT=$(kubectl get pods | grep service-deployment | grep Running | wc -l | tr -d ' ')
MONGODB_COUNT=$(kubectl get pods | grep mongodb | grep Running | wc -l | tr -d ' ')
CRASH_COUNT=$(kubectl get pods | grep CrashLoopBackOff | wc -l | tr -d ' ')
PENDING_COUNT=$(kubectl get pods | grep -E "Pending|ContainerCreating" | wc -l | tr -d ' ')

print_info "Running services: $SERVICE_COUNT (expected: 11)"
print_info "Running MongoDB: $MONGODB_COUNT (expected: 6)"
print_info "CrashLoopBackOff: $CRASH_COUNT"
print_info "Pending/ContainerCreating: $PENDING_COUNT"

if [ "$CRASH_COUNT" -eq 0 ] && [ "$PENDING_COUNT" -eq 0 ]; then
    print_info "✓ All pods should be healthy!"
else
    print_warn "Still have issues. Check the pods above."
fi

