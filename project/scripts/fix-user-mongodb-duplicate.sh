#!/bin/bash

# Fix the remaining user-mongodb duplicate

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=== Fixing user-mongodb Duplicate ===${NC}"
echo ""

# We have two ReplicaSets for user-mongodb:
# - user-mongodb-deployment-6475c8b6c9 (old, ContainerCreating)
# - user-mongodb-deployment-7b649fbd77 (good, Running)

echo "Step 1: Scale down user-mongodb-deployment..."
kubectl scale deployment user-mongodb-deployment --replicas=0
sleep 3

echo ""
echo "Step 2: Delete the old ReplicaSet (6475c8b6c9)..."
kubectl delete rs user-mongodb-deployment-6475c8b6c9 --grace-period=0 --force 2>/dev/null || echo "Already deleted"
sleep 2

echo ""
echo "Step 3: Scale back up (will use the good ReplicaSet)..."
kubectl scale deployment user-mongodb-deployment --replicas=1
sleep 5

echo ""
echo "Step 4: Check final MongoDB pod count..."
MONGODB_COUNT=$(kubectl get pods | grep mongodb | wc -l | tr -d ' ')
echo "MongoDB pods: $MONGODB_COUNT (expected: 6)"

echo ""
echo "All MongoDB ReplicaSets:"
kubectl get rs | grep mongodb

echo ""
if [ "$MONGODB_COUNT" = "6" ]; then
    echo -e "${GREEN}✓ SUCCESS! MongoDB pod count is correct!${NC}"
else
    echo -e "${YELLOW}Still have $MONGODB_COUNT MongoDB pods.${NC}"
    echo "Pods:"
    kubectl get pods | grep mongodb
fi

