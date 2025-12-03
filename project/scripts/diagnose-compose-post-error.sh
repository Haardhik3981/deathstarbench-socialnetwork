#!/bin/bash

# Diagnose the compose-post ZADD error

set -e

echo "=== Diagnosing Compose Post ZADD Error ==="
echo ""

# 1. Check compose-post-service logs
echo "=== Step 1: Compose Post Service Logs ==="
COMPOSE_POD=$(kubectl get pods -l app=compose-post-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$COMPOSE_POD" ]; then
    echo "Pod: $COMPOSE_POD"
    kubectl logs "$COMPOSE_POD" --tail=50 | grep -iE "error|fail|exception|zadd" | tail -10 || echo "  (no errors in recent logs)"
else
    echo "  No running compose-post-service pod found"
fi
echo ""

# 2. Check write-home-timeline-service logs
echo "=== Step 2: Write Home Timeline Service Logs ==="
WRITE_POD=$(kubectl get pods -l app=write-home-timeline-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$WRITE_POD" ]; then
    echo "Pod: $WRITE_POD"
    kubectl logs "$WRITE_POD" --tail=50 | grep -iE "error|fail|exception|zadd|redis" | tail -10 || echo "  (no errors in recent logs)"
else
    echo "  No running write-home-timeline-service pod found"
fi
echo ""

# 3. Check if compose-post-redis is in service-config.json
echo "=== Step 3: Checking service-config.json in ConfigMap ==="
kubectl get configmap deathstarbench-config -o jsonpath='{.data.service-config\.json}' | grep -o '"compose-post-redis"' && echo "  ✓ compose-post-redis found in ConfigMap" || echo "  ✗ compose-post-redis NOT found in ConfigMap"
echo ""

# 4. Check Redis connectivity
echo "=== Step 4: Checking Redis Services ==="
kubectl get svc | grep redis
echo ""

# 5. Check if write-home-timeline-service can reach home-timeline-redis
if [ -n "$WRITE_POD" ]; then
    echo "=== Step 5: Testing Redis connectivity from write-home-timeline-service ==="
    kubectl exec "$WRITE_POD" -- getent hosts home-timeline-redis 2>&1 || echo "  ✗ Cannot resolve home-timeline-redis"
    echo ""
fi

# 6. Check home-timeline-redis pod
echo "=== Step 6: Checking home-timeline-redis pod ==="
kubectl get pods -l app=home-timeline-redis
echo ""

echo "=== Diagnosis Complete ==="
echo ""
echo "Next steps:"
echo "1. If compose-post-redis is missing from ConfigMap, update it"
echo "2. If write-home-timeline-service can't reach Redis, check DNS"
echo "3. Check if the error is from an empty followers list"

