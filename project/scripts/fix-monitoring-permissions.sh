#!/bin/bash

# Fix monitoring pod permission issues by deleting and recreating PVCs

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_section() { echo -e "${BLUE}=== $1 ===${NC}"; }

print_section "Fixing Monitoring Pod Permissions"

print_warn "This will delete and recreate PVCs, losing existing metrics data!"
print_warn "This is necessary to fix permission issues."
echo ""
read -p "Continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Cancelled."
    exit 0
fi

# Step 1: Scale down deployments
print_section "Step 1: Scaling Down Deployments"
print_info "Scaling down Prometheus..."
kubectl scale deployment prometheus -n monitoring --replicas=0 2>/dev/null || true

print_info "Scaling down Grafana..."
kubectl scale deployment grafana -n monitoring --replicas=0 2>/dev/null || true

sleep 5

# Step 2: Delete PVCs
print_section "Step 2: Deleting PVCs (to recreate with correct permissions)"
print_warn "Deleting prometheus-pvc..."
kubectl delete pvc prometheus-pvc -n monitoring 2>/dev/null || print_warn "PVC not found or already deleted"

print_warn "Deleting grafana-pvc..."
kubectl delete pvc grafana-pvc -n monitoring 2>/dev/null || print_warn "PVC not found or already deleted"

sleep 5

# Step 3: Apply updated deployments (with securityContext)
print_section "Step 3: Applying Updated Deployments (with securityContext)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

print_info "Applying Prometheus deployment (with fsGroup fix)..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-deployment.yaml"

print_info "Applying Grafana deployment (with fsGroup fix)..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/grafana-deployment.yaml"

# Wait for PVCs to be recreated
print_info "Waiting for PVCs to be recreated..."
sleep 10

# Step 4: Scale back up
print_section "Step 4: Scaling Deployments Back Up"
print_info "Scaling Prometheus back up..."
kubectl scale deployment prometheus -n monitoring --replicas=1

print_info "Scaling Grafana back up..."
kubectl scale deployment grafana -n monitoring --replicas=1

print_info "Waiting 30 seconds for pods to start..."
sleep 30

# Step 5: Check status
print_section "Step 5: Checking Status"
kubectl get pods -n monitoring

echo ""
print_info "Check pod logs if still crashing:"
print_info "  kubectl logs -n monitoring -l app=prometheus --tail=50"
print_info "  kubectl logs -n monitoring -l app=grafana --tail=50"

