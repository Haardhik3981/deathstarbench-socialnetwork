#!/bin/bash

# Simple direct fix for MongoDB duplicates

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=== Simple MongoDB Duplicate Fix ===${NC}"
echo ""

echo "The problem: Old ReplicaSets keep getting recreated"
echo "The solution: Scale down → Delete old RS → Scale back up"
echo ""

# Step 1: Scale down MongoDB deployments that have duplicates
echo -e "${BLUE}Step 1: Scaling down duplicate MongoDB deployments...${NC}"
kubectl scale deployment social-graph-mongodb-deployment --replicas=0
kubectl scale deployment url-shorten-mongodb-deployment --replicas=0
sleep 3

# Step 2: Delete all old ReplicaSets for these deployments
echo ""
echo -e "${BLUE}Step 2: Deleting old ReplicaSets...${NC}"
kubectl delete rs -l app=social-graph-mongodb --grace-period=0 --force 2>/dev/null || true
kubectl delete rs -l app=url-shorten-mongodb --grace-period=0 --force 2>/dev/null || true

# Also delete by name
kubectl delete rs social-graph-mongodb-deployment-69b966959c --grace-period=0 --force 2>/dev/null || true
kubectl delete rs url-shorten-mongodb-deployment-fc869fc99 --grace-period=0 --force 2>/dev/null || true

sleep 3

# Step 3: Scale back up - this creates ONE new ReplicaSet
echo ""
echo -e "${BLUE}Step 3: Scaling back up (will create clean ReplicaSets)...${NC}"
kubectl scale deployment social-graph-mongodb-deployment --replicas=1
kubectl scale deployment url-shorten-mongodb-deployment --replicas=1

sleep 5

# Step 4: Check results
echo ""
echo -e "${BLUE}Step 4: Checking results...${NC}"
echo ""
echo "MongoDB ReplicaSets:"
kubectl get rs | grep mongodb

echo ""
MONGODB_COUNT=$(kubectl get pods | grep mongodb | wc -l | tr -d ' ')
echo "MongoDB pods: $MONGODB_COUNT (expected: 6)"

if [ "$MONGODB_COUNT" = "6" ]; then
    echo -e "${GREEN}✓ SUCCESS! MongoDB pod count is correct!${NC}"
else
    echo -e "${YELLOW}Still have $MONGODB_COUNT MongoDB pods.${NC}"
    echo "List of all MongoDB pods:"
    kubectl get pods | grep mongodb
fi

