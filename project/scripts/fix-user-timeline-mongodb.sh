#!/bin/bash

# Fix user-timeline-mongodb corruption issue

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
print_section "Fixing user-timeline-mongodb Corruption"

print_info "The MongoDB database is corrupted and needs repair."
print_info "The error: 'missing featureCompatibilityVersion document'"
print_info ""
print_info "Options:"
print_info "  1. Delete and recreate (will lose data - OK for testing)"
print_info "  2. Run MongoDB repair (keeps data but may take time)"
print_info ""

# Check if PVC exists
PVC_EXISTS=$(kubectl get pvc user-timeline-mongodb-pvc 2>/dev/null && echo "yes" || echo "no")

if [ "$PVC_EXISTS" = "yes" ]; then
    print_warn "PVC exists. The corrupted data is on the persistent volume."
    print_info ""
    print_info "Step 1: Scale down the deployment"
    kubectl scale deployment user-timeline-mongodb-deployment --replicas=0
    sleep 3
    
    print_info ""
    print_info "Step 2: Delete the corrupted pod's PVC (WARNING: This will delete data!)"
    print_warn "For development/testing, we'll delete the PVC to start fresh..."
    
    read -p "Delete the PVC? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deleting PVC..."
        kubectl delete pvc user-timeline-mongodb-pvc
        print_info "✓ PVC deleted"
    else
        print_info "Skipping PVC deletion. Pod will recreate but may still have corruption."
    fi
    
    print_info ""
    print_info "Step 3: Scale back up (will create new PVC)"
    kubectl scale deployment user-timeline-mongodb-deployment --replicas=1
    
    print_info ""
    print_info "✓ Deployment scaled back up. Waiting for pod to start..."
    sleep 5
    
    print_info "Pod status:"
    kubectl get pods -l app=user-timeline-mongodb
else
    print_info "No PVC found. Just restarting the pod..."
    kubectl delete pod -l app=user-timeline-mongodb --grace-period=0 --force 2>/dev/null || true
    print_info "✓ Pod deleted, will recreate"
fi

print_info ""
print_info "Note: For production, you would run MongoDB repair instead of deleting data."

