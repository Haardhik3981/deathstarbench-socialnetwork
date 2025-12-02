#!/bin/bash

# Check why user-timeline-mongodb is pending

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
print_section "Checking Why user-timeline-mongodb is Pending"

# Find the pending pod
PENDING_POD=$(kubectl get pods -l app=user-timeline-mongodb | grep -E "Pending|ContainerCreating" | awk '{print $1}' | head -1)

if [ -z "$PENDING_POD" ]; then
    print_info "No pending user-timeline-mongodb pod found. Checking all pods..."
    kubectl get pods -l app=user-timeline-mongodb
    exit 0
fi

print_info "Pending pod: $PENDING_POD"

echo ""
print_section "Pod Events (shows why it's pending)"
kubectl describe pod "$PENDING_POD" | grep -A 20 "Events:"

echo ""
print_section "Pod Status Details"
kubectl describe pod "$PENDING_POD" | grep -A 10 "Status:" | head -15

echo ""
print_section "Node Resources"
print_info "Checking if nodes have enough resources..."
kubectl describe nodes | grep -E "Allocatable:|Allocated resources:" -A 5 | head -20

echo ""
print_section "Storage Check"
print_info "Checking PVC status..."
kubectl get pvc user-timeline-mongodb-pvc -o wide

echo ""
print_section "Suggested Fixes"
print_info "If pending due to CPU: Wait for node resources or scale cluster"
print_info "If pending due to storage: Check PVC status above"
print_info "If pending due to other issues: Check events above"
