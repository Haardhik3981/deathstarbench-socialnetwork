#!/bin/bash

# Check compose-post-service logs and Redis connectivity

set -e

echo "=== Checking compose-post-service ==="
echo ""

# Check if pod is running
COMPOSE_POD=$(kubectl get pods -l app=compose-post-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$COMPOSE_POD" ]; then
    echo "✗ No compose-post-service pod found"
    kubectl get pods -l app=compose-post-service
    exit 1
fi

echo "Pod: $COMPOSE_POD"
echo ""

# Check recent logs
echo "=== Recent logs (last 30 lines) ==="
kubectl logs "$COMPOSE_POD" --tail=30

echo ""
echo "=== Errors in logs ==="
kubectl logs "$COMPOSE_POD" --tail=100 | grep -iE "error|fail|redis|zadd" | tail -20 || echo "  (no errors found)"

echo ""
echo "=== Testing Redis connectivity from compose-post-service pod ==="
echo "Testing: compose-post-redis"
kubectl exec "$COMPOSE_POD" -- getent hosts compose-post-redis 2>&1 || echo "  ✗ DNS resolution failed"

echo ""
echo "=== Checking if compose-post-redis service exists ==="
kubectl get svc compose-post-redis

echo ""
echo "=== Checking compose-post-redis pod ==="
kubectl get pods -l app=compose-post-redis

