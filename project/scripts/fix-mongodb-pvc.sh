#!/bin/bash

# Fix missing user-timeline-mongodb PVC

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
print_section "Fixing Missing user-timeline-mongodb PVC"

# Check if PVC exists
if kubectl get pvc user-timeline-mongodb-pvc &>/dev/null; then
    print_info "PVC already exists!"
    kubectl get pvc user-timeline-mongodb-pvc
    exit 0
fi

print_warn "PVC not found. Creating it now..."

# Extract PVC definition from deployment file and create it
DEPLOYMENT_FILE="/Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project/kubernetes/deployments/databases/user-timeline-mongodb-deployment.yaml"

if [ -f "$DEPLOYMENT_FILE" ]; then
    print_info "Extracting PVC definition from deployment file..."
    
    # Create temporary PVC YAML (extract the PVC part after the ---)
    TEMP_PVC=$(mktemp)
    awk '/^---$/{flag=1; next} flag' "$DEPLOYMENT_FILE" > "$TEMP_PVC"
    
    if [ -s "$TEMP_PVC" ]; then
        print_info "Creating PVC from deployment file..."
        kubectl apply -f "$TEMP_PVC"
        print_info "✓ PVC created!"
        rm -f "$TEMP_PVC"
    else
        print_warn "Could not extract PVC from deployment file. Creating manually..."
        
        # Create PVC manually
        kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: user-timeline-mongodb-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF
        print_info "✓ PVC created manually!"
    fi
else
    print_warn "Deployment file not found. Creating PVC manually..."
    
    # Create PVC manually
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: user-timeline-mongodb-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
EOF
    print_info "✓ PVC created manually!"
fi

echo ""
print_section "Waiting for PVC to be provisioned..."
sleep 5

echo ""
print_section "Checking PVC Status"
kubectl get pvc user-timeline-mongodb-pvc

echo ""
PVC_STATUS=$(kubectl get pvc user-timeline-mongodb-pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
if [ "$PVC_STATUS" = "Bound" ]; then
    print_info "✓ PVC is Bound! Pod should start now."
elif [ "$PVC_STATUS" = "Pending" ]; then
    print_warn "PVC is still Pending. Waiting for storage provisioner..."
    print_info "This may take a minute. Check status with:"
    echo "  kubectl get pvc user-timeline-mongodb-pvc"
else
    print_warn "PVC status: $PVC_STATUS"
fi

echo ""
print_section "Checking Pod Status"
kubectl get pods -l app=user-timeline-mongodb

