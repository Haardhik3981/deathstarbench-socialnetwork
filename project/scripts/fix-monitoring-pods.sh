#!/bin/bash

# Fix monitoring pods - cleanup duplicates and diagnose crashes

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

print_section "Fixing Monitoring Pods"

# Step 1: Clean up duplicate pods
print_section "Step 1: Cleaning Up Duplicate Pods"

# Scale down deployments
print_info "Scaling down Prometheus deployment..."
kubectl scale deployment prometheus -n monitoring --replicas=0 2>/dev/null || true

print_info "Scaling down Grafana deployment..."
kubectl scale deployment grafana -n monitoring --replicas=0 2>/dev/null || true

sleep 5

# Delete old ReplicaSets
print_info "Deleting old ReplicaSets..."
kubectl get rs -n monitoring --no-headers 2>/dev/null | awk '{print $1}' | while read rs; do
    if [ -n "$rs" ] && [ "$rs" != "NAME" ]; then
        print_info "  Deleting ReplicaSet: $rs"
        kubectl delete rs "$rs" -n monitoring --grace-period=0 --force 2>/dev/null || true
    fi
done

# Delete any remaining pods
print_info "Cleaning up any remaining pods..."
kubectl get pods -n monitoring --no-headers 2>/dev/null | awk '{print $1}' | while read pod; do
    if [ -n "$pod" ] && [ "$pod" != "NAME" ]; then
        print_info "  Deleting pod: $pod"
        kubectl delete pod "$pod" -n monitoring --grace-period=0 --force 2>/dev/null || true
    fi
done

sleep 5

# Step 2: Check PVCs (common cause of crashes)
print_section "Step 2: Checking PVC Status"

PVCs=$(kubectl get pvc -n monitoring --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -n "$PVCs" ]; then
    for pvc in $PVCs; do
        STATUS=$(kubectl get pvc "$pvc" -n monitoring -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        print_info "PVC $pvc status: $STATUS"
        if [ "$STATUS" != "Bound" ]; then
            print_warn "PVC $pvc is not Bound! This may cause pod crashes."
        fi
    done
else
    print_warn "No PVCs found - they will be created when pods start"
fi

# Step 3: Check pod logs for errors
print_section "Step 3: Checking Recent Pod Logs"

print_info "Checking Prometheus logs (from recent crash)..."
PROM_POD=$(kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [ -n "$PROM_POD" ] && [ "$PROM_POD" != "NAME" ]; then
    print_info "Latest Prometheus pod: $PROM_POD"
    kubectl logs "$PROM_POD" -n monitoring --tail=50 2>&1 | tail -20 || print_warn "Could not get Prometheus logs"
else
    print_warn "No Prometheus pods found"
fi

echo ""
print_info "Checking Grafana logs (from recent crash)..."
GRAFANA_POD=$(kubectl get pods -n monitoring -l app=grafana --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [ -n "$GRAFANA_POD" ] && [ "$GRAFANA_POD" != "NAME" ]; then
    print_info "Latest Grafana pod: $GRAFANA_POD"
    kubectl logs "$GRAFANA_POD" -n monitoring --tail=50 2>&1 | tail -20 || print_warn "Could not get Grafana logs"
else
    print_warn "No Grafana pods found"
fi

# Step 4: Scale back up
print_section "Step 4: Scaling Deployments Back Up"

print_info "Scaling Prometheus back up..."
kubectl scale deployment prometheus -n monitoring --replicas=1

print_info "Scaling Grafana back up..."
kubectl scale deployment grafana -n monitoring --replicas=1

print_info "Waiting 10 seconds for pods to start..."
sleep 10

# Step 5: Show current status
print_section "Step 5: Current Status"

kubectl get pods -n monitoring

echo ""
print_info "If pods are still crashing, check logs:"
print_info "  kubectl logs -n monitoring -l app=prometheus --tail=100"
print_info "  kubectl logs -n monitoring -l app=grafana --tail=100"
echo ""
print_info "Check pod events:"
print_info "  kubectl describe pod -n monitoring -l app=prometheus | tail -30"
print_info "  kubectl describe pod -n monitoring -l app=grafana | tail -30"

