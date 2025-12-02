#!/bin/bash

# Storage Cleanup Script
# This script helps identify and clean up unused PersistentVolumeClaims

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
print_info "STORAGE CLEANUP ANALYSIS"
echo "=========================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# List all PVCs with sizes
print_info "All PersistentVolumeClaims:"
echo ""
kubectl get pvc --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage,AGE:.metadata.creationTimestamp 2>/dev/null || {
    print_error "Failed to connect to cluster. Make sure kubectl is configured."
    exit 1
}

echo ""
print_info "Total storage requested:"
TOTAL=$(kubectl get pvc --all-namespaces -o jsonpath='{range .items[*]}{.spec.resources.requests.storage}{"\n"}{end}' 2>/dev/null | sed 's/Gi//' | awk '{sum+=$1} END {print sum}')
echo "  ~${TOTAL}Gi total across all PVCs"
echo ""

# Find PVCs not bound to any pod
print_info "Checking for orphaned PVCs (not mounted by any pod)..."
echo ""

ORPHANED_PVCS=()
ALL_PVCS=$(kubectl get pvc --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null)

while IFS= read -r line; do
    if [ -z "$line" ]; then
        continue
    fi
    
    NAMESPACE=$(echo "$line" | awk '{print $1}')
    PVC_NAME=$(echo "$line" | awk '{print $2}')
    
    # Check if PVC is mounted by any pod
    MOUNTED=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.spec.volumes[*].persistentVolumeClaim.claimName}{"\n"}{end}' 2>/dev/null | grep -c "^${PVC_NAME}$" || echo "0")
    
    if [ "$MOUNTED" -eq 0 ]; then
        ORPHANED_PVCS+=("${NAMESPACE}/${PVC_NAME}")
        print_warn "  Orphaned PVC: ${NAMESPACE}/${PVC_NAME}"
    fi
done <<< "$ALL_PVCS"

echo ""
if [ ${#ORPHANED_PVCS[@]} -eq 0 ]; then
    print_info "No orphaned PVCs found"
else
    print_warn "Found ${#ORPHANED_PVCS[@]} orphaned PVC(s)"
    echo ""
    print_info "To delete orphaned PVCs, run:"
    for pvc in "${ORPHANED_PVCS[@]}"; do
        NAMESPACE=$(echo "$pvc" | cut -d'/' -f1)
        PVC_NAME=$(echo "$pvc" | cut -d'/' -f2)
        echo "  kubectl delete pvc ${PVC_NAME} -n ${NAMESPACE}"
    done
fi

echo ""
print_info "Checking for duplicate PVCs (same name pattern)..."
echo ""

# Group PVCs by name pattern
kubectl get pvc --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort | uniq -d | while read -r name; do
    print_warn "  Duplicate PVC name found: ${name}"
    kubectl get pvc --all-namespaces | grep "$name" || true
done

echo ""
echo "=========================================="
print_info "CLEANUP RECOMMENDATIONS"
echo "=========================================="
echo ""
print_info "1. Delete orphaned PVCs (shown above)"
print_info "2. Delete old/failed deployment PVCs:"
echo "   kubectl delete pvc --all-namespaces --selector=app=<old-app-name>"
echo ""
print_info "3. Delete all PVCs and start fresh (DESTRUCTIVE):"
echo "   kubectl delete pvc --all-namespaces --all"
echo ""
print_info "4. Check GCP Console for unused disks:"
echo "   https://console.cloud.google.com/compute/disks"
echo ""
print_info "5. Reduce storage sizes in deployment files:"
echo "   - MongoDB: 10Gi -> 2Gi (for development)"
echo "   - Prometheus: 20Gi -> 5Gi (for development)"
echo "   - Grafana: 5Gi -> 1Gi (for development)"

