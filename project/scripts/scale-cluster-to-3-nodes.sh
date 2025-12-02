#!/bin/bash

# Scale cluster to 3 nodes to fix CPU constraint

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

CLUSTER_NAME="${GKE_CLUSTER:-social-network-cluster}"
ZONE="${GKE_ZONE:-us-central1-a}"

print_info "Scaling cluster to 3 nodes..."
print_info "Current status: 2 nodes at 99% CPU"
print_info "Total CPU requested: 5685m"
print_info "Total CPU available (2 nodes): ~3860m"
print_info "Need: 3 nodes (~5790m total CPU)"
echo ""

print_info "Starting cluster resize..."
gcloud container clusters resize "$CLUSTER_NAME" \
  --num-nodes=3 \
  --zone="$ZONE"

print_info ""
print_info "✓ Cluster resize initiated!"
print_info "This will take 2-5 minutes."
echo ""
print_info "Watch for new node:"
echo "  kubectl get nodes -w"
echo ""
print_info "After new node is ready, nginx-thrift pods should schedule automatically."

