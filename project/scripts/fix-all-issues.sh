#!/bin/bash

# Fix all current issues identified in the audit

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
print_section "Fixing All Current Issues"

# Issue 1: Delete old nginx deployment
echo ""
print_section "Fix 1: Delete Old nginx Deployment"
print_info "The old nginx-deployment is not needed (we use nginx-thrift)"
if kubectl get deployment nginx-deployment &>/dev/null; then
    print_info "Deleting old nginx-deployment..."
    kubectl delete deployment nginx-deployment
    print_info "✓ Deleted"
else
    print_info "Already deleted"
fi

# Issue 2: Fix user-service duplicate
echo ""
print_section "Fix 2: Fix user-service Duplicate (2 pods → 1)"
USER_SERVICE_PODS=$(kubectl get pods -l app=user-service | grep Running | wc -l | tr -d ' ')
if [ "$USER_SERVICE_PODS" -gt 1 ]; then
    print_warn "Found $USER_SERVICE_PODS user-service pods (should be 1)"
    print_info "Scaling user-service-deployment to 1 replica..."
    kubectl scale deployment user-service-deployment --replicas=1
    sleep 3
    print_info "✓ Scaled to 1"
else
    print_info "Already at correct replica count"
fi

# Issue 3: Fix user-timeline-mongodb corruption
echo ""
print_section "Fix 3: Fix user-timeline-mongodb Corruption"
print_warn "MongoDB database is corrupted (missing featureCompatibilityVersion)"
print_info "Solution: Delete PVC and let it recreate (clean start)"
print_info ""

# Scale down
print_info "Scaling down deployment..."
kubectl scale deployment user-timeline-mongodb-deployment --replicas=0
sleep 3

# Delete the corrupted pod
print_info "Deleting corrupted pod..."
kubectl delete pod -l app=user-timeline-mongodb --grace-period=0 --force 2>/dev/null || true
sleep 2

# Delete PVC to start fresh
print_info "Deleting PVC to start fresh (will lose data, OK for testing)..."
kubectl delete pvc user-timeline-mongodb-pvc 2>/dev/null && print_info "✓ PVC deleted" || print_warn "PVC not found or already deleted"

# Scale back up
print_info "Scaling back up (will create new PVC)..."
kubectl scale deployment user-timeline-mongodb-deployment --replicas=1
sleep 5

print_info "✓ MongoDB deployment reset"

# Issue 4: Check nginx-thrift
echo ""
print_section "Fix 4: Check nginx-thrift Status"
NGINX_POD=$(kubectl get pods -l app=nginx-thrift | grep -v NAME | awk '{print $1}' | head -1)
if [ -n "$NGINX_POD" ]; then
    print_info "nginx-thrift pod: $NGINX_POD"
    print_info "Status: $(kubectl get pod "$NGINX_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo 'unknown')"
    print_info ""
    print_info "Recent logs (last 10 lines):"
    kubectl logs "$NGINX_POD" --tail=10 2>&1 | tail -10 || print_warn "Could not get logs"
    print_info ""
    print_warn "If still crashing, check ConfigMap mounts and configuration"
else
    print_warn "No nginx-thrift pod found"
fi

echo ""
print_section "Waiting for fixes to stabilize..."
sleep 10

echo ""
print_section "Final Status Check"
RUNNING_SERVICES=$(kubectl get pods | grep service-deployment | grep Running | wc -l | tr -d ' ')
RUNNING_MONGODB=$(kubectl get pods | grep mongodb | grep Running | wc -l | tr -d ' ')
CRASH_COUNT=$(kubectl get pods | grep CrashLoopBackOff | wc -l | tr -d ' ')
PENDING_COUNT=$(kubectl get pods | grep -E "Pending|ContainerCreating" | wc -l | tr -d ' ')

print_info "Running services: $RUNNING_SERVICES (expected: 11)"
print_info "Running MongoDB: $RUNNING_MONGODB (expected: 6)"
print_info "CrashLoopBackOff: $CRASH_COUNT (expected: 0)"
print_info "Pending/ContainerCreating: $PENDING_COUNT (expected: 0)"

echo ""
if [ "$CRASH_COUNT" -eq 0 ] && [ "$PENDING_COUNT" -eq 0 ] && [ "$RUNNING_SERVICES" -eq 11 ] && [ "$RUNNING_MONGODB" -eq 6 ]; then
    print_info "✓ SUCCESS! All pods should be healthy!"
else
    print_warn "Still have issues. Remaining problems:"
    [ "$CRASH_COUNT" -gt 0 ] && kubectl get pods | grep CrashLoopBackOff
    [ "$PENDING_COUNT" -gt 0 ] && kubectl get pods | grep -E "Pending|ContainerCreating"
fi

