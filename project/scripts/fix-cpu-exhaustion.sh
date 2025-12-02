#!/bin/bash

# Script to fix CPU exhaustion issue

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

CLUSTER_NAME="${GKE_CLUSTER:-social-network-cluster}"
ZONE="${GKE_ZONE:-us-central1-a}"

echo ""
print_step "=== CPU Exhaustion Fix ==="
echo ""

print_info "Current CPU usage:"
kubectl describe nodes | grep -A 3 "Allocated resources" | head -5

echo ""
print_step "Step 1: Clean up old crashed pods"
print_info "Deleting pods in CrashLoopBackOff state..."
CRASHED_PODS=$(kubectl get pods | grep CrashLoopBackOff | awk '{print $1}' | tr '\n' ' ')

if [ -n "$CRASHED_PODS" ]; then
    print_info "Found crashed pods. Deleting..."
    for pod in $CRASHED_PODS; do
        echo "  - $pod"
        kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
    done
    print_info "✓ Deleted crashed pods"
else
    print_info "No crashed pods found"
fi

echo ""
print_step "Step 2: Wait for cleanup to complete"
print_info "Waiting 10 seconds for resources to be freed..."
sleep 10

echo ""
print_info "CPU usage after cleanup:"
kubectl describe nodes | grep -A 3 "Allocated resources" | head -5

echo ""
print_step "Step 3: Check if we have enough CPU now"
CPU_USAGE=$(kubectl describe nodes | grep -A 3 "Allocated resources" | grep cpu | awk '{print $2}' | sed 's/[()]//g' | sed 's/%//')
CPU_NUM=$(echo "$CPU_USAGE" | sed 's/[^0-9]//g')

if [ -z "$CPU_NUM" ]; then
    print_warn "Could not determine CPU usage percentage"
    print_info "Checking manually..."
    kubectl describe nodes | grep -A 5 "Allocated resources"
else
    if [ "$CPU_NUM" -lt 90 ]; then
        print_info "✓ CPU usage is below 90% ($CPU_USAGE). Pods should be able to schedule now."
    else
        print_warn "CPU usage is still high ($CPU_USAGE). Consider scaling up cluster."
        echo ""
        print_info "To scale up cluster, run:"
        echo "  gcloud container clusters resize $CLUSTER_NAME --num-nodes=2 --zone=$ZONE"
        echo ""
        read -p "Do you want to scale up the cluster now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Scaling up cluster..."
            gcloud container clusters resize "$CLUSTER_NAME" \
                --num-nodes=2 \
                --zone="$ZONE"
            print_info "✓ Cluster scaling initiated. This may take 2-5 minutes."
            print_info "Watch progress: kubectl get nodes -w"
        fi
    fi
fi

echo ""
print_step "Step 4: Check pod status"
print_info "Current pod status:"
kubectl get pods | grep -E "NAME|Pending|Running" | head -15

echo ""
print_info "Done! Monitor pods with: kubectl get pods -w"

