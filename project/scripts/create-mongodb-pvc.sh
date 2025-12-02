#!/bin/bash

# Create the missing user-timeline-mongodb PVC

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Creating Missing user-timeline-mongodb PVC ===${NC}"
echo ""

# Check if PVC already exists
if kubectl get pvc user-timeline-mongodb-pvc &>/dev/null; then
    echo -e "${GREEN}[INFO]${NC} PVC already exists!"
    kubectl get pvc user-timeline-mongodb-pvc
    exit 0
fi

echo -e "${GREEN}[INFO]${NC} Creating PVC..."

# Create the PVC directly
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

echo ""
echo -e "${GREEN}[INFO]${NC} ✓ PVC created! Waiting for it to be bound..."
sleep 3

echo ""
echo -e "${BLUE}=== PVC Status ===${NC}"
kubectl get pvc user-timeline-mongodb-pvc

echo ""
echo -e "${BLUE}=== Pod Status ===${NC}"
kubectl get pods -l app=user-timeline-mongodb

echo ""
echo -e "${GREEN}[INFO]${NC} The pod should start once the PVC is bound (usually takes a few seconds)."
echo "Monitor with: kubectl get pods -l app=user-timeline-mongodb -w"

