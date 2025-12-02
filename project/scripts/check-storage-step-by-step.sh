#!/bin/bash

# Step-by-step storage diagnosis script

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
print_step "=== Step 1: Check if storage class 'standard-rwo' exists ==="
kubectl get storageclass standard-rwo
if [ $? -eq 0 ]; then
    print_info "✓ Storage class 'standard-rwo' exists"
    kubectl describe storageclass standard-rwo
else
    print_warn "✗ Storage class 'standard-rwo' does NOT exist"
    echo ""
    print_info "Available storage classes:"
    kubectl get storageclass
fi

echo ""
print_step "=== Step 2: Check why a specific PVC is pending ==="
PVC_NAME="user-mongodb-pvc"
print_info "Checking PVC: $PVC_NAME"
echo ""
kubectl describe pvc "$PVC_NAME" | tail -40

echo ""
print_step "=== Step 3: Check node storage capacity ==="
print_info "Checking if nodes have storage available..."
kubectl describe nodes | grep -A 10 "System Info" | head -15 || kubectl describe nodes | grep -i storage || print_info "Storage info not directly available in node description"

echo ""
print_step "=== Summary ==="
print_info "Next actions will be suggested based on findings above."

