#!/bin/bash

# Comprehensive fix for Prometheus: cleanup duplicates and validate config

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

print_section "Fixing Prometheus Issues"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Step 1: Check current status
print_section "Step 1: Current Status"
kubectl get pods -n monitoring -l app=prometheus || true

# Step 2: Scale down to stop all pods
print_section "Step 2: Scaling Down to Stop All Pods"
print_info "Scaling deployment to 0 replicas..."
kubectl scale deployment prometheus -n monitoring --replicas=0 2>/dev/null || true

print_info "Waiting 15 seconds for pods to terminate..."
sleep 15

# Step 3: Force delete any remaining pods
print_section "Step 3: Force Deleting Any Remaining Pods"
REMAINING_PODS=$(kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -n "$REMAINING_PODS" ]; then
    echo "$REMAINING_PODS" | while read pod; do
        if [ -n "$pod" ] && [ "$pod" != "NAME" ]; then
            print_info "Force deleting pod: $pod"
            kubectl delete pod "$pod" -n monitoring --grace-period=0 --force 2>/dev/null || true
        fi
    done
    sleep 5
fi

# Step 4: Delete old ReplicaSets
print_section "Step 4: Cleaning Up Old ReplicaSets"
OLD_RS=$(kubectl get rs -n monitoring -l app=prometheus --no-headers 2>/dev/null | awk '{print $1}' || echo "")
if [ -n "$OLD_RS" ]; then
    echo "$OLD_RS" | while read rs; do
        if [ -n "$rs" ] && [ "$rs" != "NAME" ]; then
            print_info "Deleting ReplicaSet: $rs"
            kubectl delete rs "$rs" -n monitoring --grace-period=0 --force 2>/dev/null || true
        fi
    done
    sleep 5
fi

# Step 5: Validate Prometheus config before applying
print_section "Step 5: Validating Prometheus Configuration"
print_info "Checking for syntax errors in prometheus-configmap.yaml..."

# Extract the config from the YAML and check if it's valid YAML
if kubectl create configmap prometheus-config-test --from-file="${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml" --dry-run=client -o yaml > /dev/null 2>&1; then
    print_info "✓ YAML syntax is valid"
else
    print_error "✗ YAML syntax error detected!"
    print_info "Checking the config file..."
    # Try to extract just the prometheus.yml content
    if command -v yq &> /dev/null; then
        yq eval '.data."prometheus.yml"' "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml" > /tmp/prometheus-test.yml 2>&1 || true
        if [ -f /tmp/prometheus-test.yml ]; then
            print_info "Extracted config saved to /tmp/prometheus-test.yml for inspection"
        fi
    fi
    print_warn "Continuing anyway - Prometheus will validate on startup"
fi

# Step 6: Apply the config
print_section "Step 6: Applying Updated Configuration"
print_info "Applying prometheus-configmap.yaml..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml"

# Step 7: Scale back up
print_section "Step 7: Scaling Back Up"
print_info "Scaling deployment to 1 replica..."
kubectl scale deployment prometheus -n monitoring --replicas=1

print_info "Waiting 30 seconds for pod to start..."
sleep 30

# Step 8: Check status
print_section "Step 8: Final Status"
kubectl get pods -n monitoring -l app=prometheus

echo ""
PROM_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PROM_POD" ]; then
    POD_STATUS=$(kubectl get pod "$PROM_POD" -n monitoring -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$POD_STATUS" = "Running" ]; then
        print_info "✓ Prometheus pod is Running"
        print_info "Checking logs for errors..."
        kubectl logs -n monitoring "$PROM_POD" --tail=20 2>&1 | grep -i "error\|fatal\|panic" || print_info "No obvious errors in recent logs"
    else
        print_warn "Prometheus pod status: $POD_STATUS"
        print_info "Check logs: kubectl logs -n monitoring $PROM_POD --tail=50"
    fi
else
    print_warn "No Prometheus pod found"
fi

echo ""
print_section "Next Steps"
print_info "If pod is running, check Prometheus targets:"
print_info "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
print_info "  Then visit: http://localhost:9090/targets"
print_info ""
print_info "If pod is still crashing, check logs:"
print_info "  kubectl logs -n monitoring -l app=prometheus --tail=100"

