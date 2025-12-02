#!/bin/bash

# Complete Cleanup Script - Removes Everything for Fresh Deployment
# This deletes all deployments, services, ConfigMaps, and PVCs

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo ""
echo "=========================================="
echo "  Complete Cleanup Script"
echo "  Removes ALL DeathStarBench Resources"
echo "=========================================="
echo ""

# Safety check
print_warn "This will delete ALL deployments, services, ConfigMaps, and PVCs!"
print_warn "This is IRREVERSIBLE - all data will be lost!"
echo ""

read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Cleanup cancelled."
    exit 0
fi

echo ""
print_section "Starting Cleanup..."

# Step 1: Delete all deployments
print_section "Step 1: Deleting All Deployments"
print_info "This removes all pods and their containers..."

DEPLOYMENTS=$(kubectl get deployment -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$DEPLOYMENTS" ]; then
    for deploy in $DEPLOYMENTS; do
        print_info "  Deleting deployment: $deploy"
        kubectl delete deployment "$deploy" --grace-period=30 2>/dev/null || true
    done
    print_info "✓ All deployments deleted"
else
    print_info "No deployments found"
fi

# Wait for pods to terminate
print_info "Waiting 10 seconds for pods to terminate..."
sleep 10

# Step 2: Delete all Services
print_section "Step 2: Deleting All Services"
print_info "Removing Kubernetes Services (network endpoints)..."

SERVICES=$(kubectl get svc -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | grep -v "kubernetes" || echo "")

if [ -n "$SERVICES" ]; then
    for svc in $SERVICES; do
        print_info "  Deleting service: $svc"
        kubectl delete svc "$svc" 2>/dev/null || true
    done
    print_info "✓ All services deleted"
else
    print_info "No services found (except default kubernetes service)"
fi

# Step 3: Delete all ConfigMaps
print_section "Step 3: Deleting All ConfigMaps"
print_info "Removing configuration files..."

CONFIGMAPS=$(kubectl get configmap -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | grep -v "kube-root-ca.crt" || echo "")

if [ -n "$CONFIGMAPS" ]; then
    for cm in $CONFIGMAPS; do
        print_info "  Deleting ConfigMap: $cm"
        kubectl delete configmap "$cm" 2>/dev/null || true
    done
    print_info "✓ All ConfigMaps deleted"
else
    print_info "No ConfigMaps found"
fi

# Step 4: Delete all PVCs (Persistent Volume Claims)
print_section "Step 4: Deleting All Persistent Volume Claims"
print_warn "This will delete all database data!"

PVCs=$(kubectl get pvc -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PVCs" ]; then
    print_info "Found PVCs: $(echo $PVCs | tr ' ' '\n' | wc -l | tr -d ' ')"
    for pvc in $PVCs; do
        print_warn "  Deleting PVC: $pvc (this deletes persistent data!)"
        kubectl delete pvc "$pvc" 2>/dev/null || true
    done
    print_info "✓ All PVCs deleted"
else
    print_info "No PVCs found"
fi

# Step 5: Delete any remaining pods (orphaned)
print_section "Step 5: Cleaning Up Any Remaining Pods"
REMAINING_PODS=$(kubectl get pods --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -n "$REMAINING_PODS" ]; then
    print_warn "Found remaining pods, deleting..."
    for pod in $REMAINING_PODS; do
        print_info "  Deleting pod: $pod"
        kubectl delete pod "$pod" --grace-period=0 --force 2>/dev/null || true
    done
    print_info "✓ Remaining pods deleted"
else
    print_info "No remaining pods"
fi

# Step 6: Delete any remaining ReplicaSets (orphaned)
print_section "Step 6: Cleaning Up Orphaned ReplicaSets"
REPLICASETS=$(kubectl get rs --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -n "$REPLICASETS" ]; then
    print_info "Found ReplicaSets, deleting..."
    for rs in $REPLICASETS; do
        print_info "  Deleting ReplicaSet: $rs"
        kubectl delete rs "$rs" --grace-period=0 --force 2>/dev/null || true
    done
    print_info "✓ ReplicaSets cleaned up"
else
    print_info "No ReplicaSets found"
fi

# Wait a bit
print_info "Waiting 5 seconds for cleanup to complete..."
sleep 5

# Final status
print_section "Cleanup Complete - Final Status"
echo ""

# Check what's left
DEPLOYMENTS_LEFT=$(kubectl get deployment --no-headers 2>/dev/null | wc -l | tr -d ' ')
SERVICES_LEFT=$(kubectl get svc --no-headers 2>/dev/null | grep -v "kubernetes" | wc -l | tr -d ' ')
CONFIGMAPS_LEFT=$(kubectl get configmap --no-headers 2>/dev/null | grep -v "kube-root-ca.crt" | wc -l | tr -d ' ')
PVCS_LEFT=$(kubectl get pvc --no-headers 2>/dev/null | wc -l | tr -d ' ')
PODS_LEFT=$(kubectl get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')

print_info "Remaining resources:"
echo "  Deployments: $DEPLOYMENTS_LEFT"
echo "  Services: $SERVICES_LEFT (excluding default kubernetes service)"
echo "  ConfigMaps: $CONFIGMAPS_LEFT (excluding system ConfigMaps)"
echo "  PVCs: $PVCS_LEFT"
echo "  Pods: $PODS_LEFT"

if [ "$DEPLOYMENTS_LEFT" = "0" ] && [ "$SERVICES_LEFT" = "0" ] && [ "$CONFIGMAPS_LEFT" = "0" ] && [ "$PVCS_LEFT" = "0" ] && [ "$PODS_LEFT" = "0" ]; then
    echo ""
    print_info "✓✓✓ Complete cleanup successful! ✓✓✓"
    echo ""
    print_info "You can now run ./deploy-everything.sh for a fresh deployment."
else
    echo ""
    print_warn "Some resources may still remain:"
    [ "$PODS_LEFT" -gt 0 ] && kubectl get pods
    [ "$DEPLOYMENTS_LEFT" -gt 0 ] && kubectl get deployments
    [ "$SERVICES_LEFT" -gt 0 ] && kubectl get svc | grep -v "kubernetes"
    [ "$CONFIGMAPS_LEFT" -gt 0 ] && kubectl get configmap | grep -v "kube-root-ca.crt"
fi

echo ""
echo "=========================================="
print_info "Cleanup script completed!"
echo "=========================================="

