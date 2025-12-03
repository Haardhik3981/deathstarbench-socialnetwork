#!/bin/bash

# Deep dive into the ZADD error

set -e

echo "=== Deep Dive: ZADD Error Investigation ==="
echo ""

# Check home-timeline-service logs for Redis errors
echo "=== Step 1: home-timeline-service logs (last 50 lines) ==="
HOME_POD=$(kubectl get pods -l app=home-timeline-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$HOME_POD" ]; then
    echo "Pod: $HOME_POD"
    kubectl logs "$HOME_POD" --tail=50 | grep -iE "error|fail|exception|zadd|redis|follower" | tail -20 || echo "  (no relevant errors found)"
else
    echo "  No running home-timeline-service pod found"
fi
echo ""

# Check compose-post-service logs
echo "=== Step 2: compose-post-service logs (last 50 lines) ==="
COMPOSE_POD=$(kubectl get pods -l app=compose-post-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$COMPOSE_POD" ]; then
    echo "Pod: $COMPOSE_POD"
    kubectl logs "$COMPOSE_POD" --tail=50 | grep -iE "error|fail|exception|zadd" | tail -20 || echo "  (no relevant errors found)"
else
    echo "  No running compose-post-service pod found"
fi
echo ""

# Check if social-graph-service is actually returning data
echo "=== Step 3: Testing social-graph-service directly ==="
SOCIAL_POD=$(kubectl get pods -l app=social-graph-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SOCIAL_POD" ]; then
    echo "Pod: $SOCIAL_POD"
    echo "Recent logs:"
    kubectl logs "$SOCIAL_POD" --tail=20 | tail -10
else
    echo "  No running social-graph-service pod found"
fi
echo ""

# Check Redis connectivity and test
echo "=== Step 4: Testing Redis directly ==="
REDIS_POD=$(kubectl get pods -l app=home-timeline-redis --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$REDIS_POD" ]; then
    echo "Testing Redis connection from home-timeline-service pod:"
    kubectl exec "$HOME_POD" -- sh -c "command -v redis-cli >/dev/null 2>&1 && redis-cli -h home-timeline-redis -p 6379 PING 2>&1 || echo 'redis-cli not available in pod'" 2>&1 || echo "  Cannot test Redis connection"
    echo ""
fi

# Check if the issue is with empty followers
echo "=== Step 5: Hypothesis Check ==="
echo "The error 'ZADD: no key specified' might occur when:"
echo "1. A user has no followers (empty followers_id_set)"
echo "2. The Redis client is called incorrectly"
echo "3. There's a bug in the Redis client library"
echo ""
echo "Let's check if new users (who have no followers) are causing this..."
echo ""

# Check write-home-timeline-service logs too
echo "=== Step 6: write-home-timeline-service logs ==="
WRITE_POD=$(kubectl get pods -l app=write-home-timeline-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$WRITE_POD" ]; then
    echo "Pod: $WRITE_POD"
    kubectl logs "$WRITE_POD" --tail=30 | grep -iE "error|fail|exception|zadd|redis" | tail -15 || echo "  (no relevant errors found)"
else
    echo "  No running write-home-timeline-service pod found"
fi
echo ""

echo "=== Analysis ==="
echo ""
echo "If you see 'Failed to get followers' in home-timeline-service logs,"
echo "that means social-graph-service is not responding correctly."
echo ""
echo "If you see Redis connection errors, that's the issue."
echo ""
echo "The 'ZADD: no key specified' error suggests the Redis client is being"
echo "called with an empty or null key. This could happen if:"
echo "- followers_id_set is empty AND there's a bug in the code"
echo "- The Redis client library has a bug"
echo "- There's an exception being caught and re-thrown incorrectly"

