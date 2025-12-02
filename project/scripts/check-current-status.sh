#!/bin/bash

# Comprehensive status check script

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo ""
print_step "=== Step 1: Check CPU Usage ==="
print_info "Current node CPU allocation:"
kubectl describe nodes | grep -A 3 "Allocated resources" | head -5

echo ""
print_step "=== Step 2: Check New Crashing Pod Logs (config fix test) ==="
print_info "Checking logs of a newly started pod to see if config issue is fixed..."
CRASHING_NEW_POD=$(kubectl get pods | grep -E "compose-post-service-deployment-79c7c5b8b7-984v4|post-storage-service-deployment-5c8566f4c-nxzmz" | grep CrashLoopBackOff | head -1 | awk '{print $1}')
if [ -n "$CRASHING_NEW_POD" ] && [ "$CRASHING_NEW_POD" != "NAME" ]; then
    print_info "Checking pod: $CRASHING_NEW_POD"
    echo ""
    kubectl logs "$CRASHING_NEW_POD" --tail=30 2>&1 | head -40
else
    print_warn "No new crashing pods found to check"
fi

echo ""
print_step "=== Step 3: Count Pods by Status ==="
print_info "Pending pods:"
PENDING_COUNT=$(kubectl get pods | grep -c Pending || echo "0")
echo "  $PENDING_COUNT pods pending"

print_info "Crashing pods:"
CRASH_COUNT=$(kubectl get pods | grep -c CrashLoopBackOff || echo "0")
echo "  $CRASH_COUNT pods crashing"

print_info "Running pods:"
RUNNING_COUNT=$(kubectl get pods | grep -c Running || echo "0")
echo "  $RUNNING_COUNT pods running"

echo ""
print_step "=== Step 4: Check for Duplicate Pods ==="
print_info "Pods from same deployment (duplicates):"
kubectl get pods | awk '{print $1}' | grep -E "deployment-" | cut -d'-' -f1-4 | sort | uniq -d | head -5

echo ""
print_step "=== Summary ==="
if [ "$PENDING_COUNT" -gt 10 ]; then
    print_warn "Still many pending pods - likely still CPU constrained"
fi

if [ "$CRASH_COUNT" -gt 0 ]; then
    print_info "Some pods are crashing - need to check if config fix worked or new error"
fi

