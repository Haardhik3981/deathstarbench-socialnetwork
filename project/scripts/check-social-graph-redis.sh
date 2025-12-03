#!/bin/bash

# Check social-graph-redis connectivity

set -e

echo "=== Checking social-graph-redis ==="
echo ""

# Check if Redis pod exists
echo "=== Step 1: Checking social-graph-redis pod ==="
kubectl get pods -l app=social-graph-redis
echo ""

# Check if Redis service exists
echo "=== Step 2: Checking social-graph-redis service ==="
kubectl get svc social-graph-redis
echo ""

# Test connectivity from social-graph-service
echo "=== Step 3: Testing connectivity from social-graph-service ==="
SOCIAL_POD=$(kubectl get pods -l app=social-graph-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SOCIAL_POD" ]; then
    echo "Pod: $SOCIAL_POD"
    echo "Testing DNS resolution:"
    kubectl exec "$SOCIAL_POD" -- getent hosts social-graph-redis 2>&1 || echo "  ✗ Cannot resolve social-graph-redis"
    echo ""
else
    echo "  No running social-graph-service pod found"
    echo ""
fi

# Check social-graph-service logs for Redis connection errors
echo "=== Step 4: Checking for Redis connection errors ==="
if [ -n "$SOCIAL_POD" ]; then
    kubectl logs "$SOCIAL_POD" --tail=100 | grep -iE "redis|connection|error" | tail -10 || echo "  (no Redis errors found)"
    echo ""
fi

echo "=== Analysis ==="
echo ""
echo "The error 'ZADD: no key specified' occurs at line 607 in GetFollowers"
echo "when trying to update Redis with an empty redis_zset (user has no followers)."
echo ""
echo "This is likely a bug in the Redis client library when called with empty iterators."
echo "However, the code should check if redis_zset is empty before calling zadd."

