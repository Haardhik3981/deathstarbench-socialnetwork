#!/bin/bash

# Script to fix common issues causing pods to be pending

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

cd "$PROJECT_ROOT"

print_info "=== Checking PVC Status ==="
PVC_STATUS=$(kubectl get pvc 2>&1)
echo "$PVC_STATUS"

# Check if any PVCs are pending
if echo "$PVC_STATUS" | grep -q "Pending"; then
    print_warn "\nSome PVCs are pending. Checking why..."
    
    # Check storage classes
    print_info "\nAvailable storage classes:"
    kubectl get storageclass
    
    # Check if there's a default storage class
    DEFAULT_SC=$(kubectl get storageclass -o json | grep -i '"is-default-class":true' || echo "")
    if [ -z "$DEFAULT_SC" ]; then
        print_warn "\nNo default storage class found. Setting standard as default..."
        if kubectl get storageclass standard &>/dev/null; then
            kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
            print_info "Set 'standard' as default storage class"
        else
            print_warn "Storage class 'standard' not found. Please check available storage classes above."
        fi
    fi
fi

print_info "\n=== Checking Node Resources ==="
kubectl describe nodes | grep -A 5 "Allocated resources" | head -20

print_info "\n=== Checking Specific Pending Pod ==="
PENDING_POD=$(kubectl get pods | grep Pending | head -1 | awk '{print $1}')
if [ -n "$PENDING_POD" ] && [ "$PENDING_POD" != "NAME" ]; then
    print_info "Analyzing pending pod: $PENDING_POD"
    kubectl describe pod "$PENDING_POD" | tail -40
fi

print_info "\n=== Recommendation: Clean Up Old Pods ==="
print_warn "You have both old (crashing) and new (pending) pods."
print_info "Deleting old crashing pods will allow new ones to start:"
echo ""
echo "To delete old crashing pods, run:"
echo "  kubectl delete pod <old-pod-name>"
echo ""
echo "Or delete all pods in CrashLoopBackOff:"
echo "  kubectl delete pod \$(kubectl get pods | grep CrashLoopBackOff | awk '{print \$1}')"

