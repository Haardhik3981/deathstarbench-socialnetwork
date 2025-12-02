#!/bin/bash

# Check why nginx-thrift pods are pending

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

PENDING_NGINX=$(kubectl get pods | grep nginx-thrift | grep Pending | head -1 | awk '{print $1}')

if [ -z "$PENDING_NGINX" ] || [ "$PENDING_NGINX" == "NAME" ]; then
    print_warn "No pending nginx-thrift pods found"
    exit 0
fi

print_step "=== Checking Why nginx-thrift Pod is Pending ==="
print_info "Pod: $PENDING_NGINX"
echo ""

print_info "Pod events (why it can't schedule):"
kubectl describe pod "$PENDING_NGINX" | grep -A 20 "Events:" | tail -25

echo ""
print_step "=== Checking Node Resources ==="
print_info "CPU/Memory usage on nodes:"
kubectl describe nodes | grep -A 5 "Allocated resources" | head -15

echo ""
print_step "=== Checking How Many Nodes ==="
kubectl get nodes

echo ""
print_step "=== Checking CPU Requests for All Pods ==="
print_info "Total CPU requested by all pods:"
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.requests.cpu}{"\n"}{end}' | grep -v "^$" | awk '{sum+=$2} END {print "Total CPU requests: " sum "m"}'

