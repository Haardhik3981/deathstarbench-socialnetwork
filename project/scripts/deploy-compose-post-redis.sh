#!/bin/bash

# Deploy compose-post-redis deployment and service

set -e

echo "=== Deploying compose-post-redis ==="
echo ""

# Apply deployment
echo "Step 1: Deploying compose-post-redis deployment..."
kubectl apply -f kubernetes/deployments/databases/redis-deployments.yaml
echo "✓ Deployment applied"
echo ""

# Apply service
echo "Step 2: Deploying compose-post-redis service..."
kubectl apply -f kubernetes/services/all-databases.yaml
echo "✓ Service applied"
echo ""

# Wait for pod to be ready
echo "Step 3: Waiting for compose-post-redis pod..."
sleep 5
kubectl wait --for=condition=ready pod -l app=compose-post-redis --timeout=60s || echo "⚠ Pod not ready yet"
echo ""

# Verify
echo "Step 4: Verifying deployment..."
kubectl get pods -l app=compose-post-redis
kubectl get svc compose-post-redis
echo ""

echo "=== Done ==="
echo ""
echo "Now restart compose-post-service to pick up the Redis connection:"
echo "  kubectl rollout restart deployment/compose-post-service-deployment"

