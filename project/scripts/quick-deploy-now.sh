#!/bin/bash
# Quick deploy - get everything running NOW

echo "=== Quick Deploy - Getting Everything Running ==="
echo ""

cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

echo "1. Applying updated nginx-thrift deployment (lua-scripts temporarily disabled)..."
kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml

echo ""
echo "2. Restarting nginx-thrift..."
kubectl rollout restart deployment/nginx-thrift-deployment

echo ""
echo "3. Waiting 10 seconds..."
sleep 10

echo ""
echo "4. Checking pod status..."
kubectl get pods -l app=nginx-thrift

echo ""
echo "✓ Done! nginx-thrift should start now (lua scripts disabled temporarily)"
echo ""
echo "Once this works, we can fix the lua-scripts ConfigMap properly later."

