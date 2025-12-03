#!/bin/bash

# Check home-timeline-service status and logs

set -e

echo "=== Checking home-timeline-service ==="
echo ""

# Check if pod exists
echo "=== Step 1: Checking pods ==="
kubectl get pods -l app=home-timeline-service
echo ""

# Check service
echo "=== Step 2: Checking service ==="
kubectl get svc home-timeline-service 2>&1 || echo "  ✗ Service not found"
echo ""

# Check logs
HOME_POD=$(kubectl get pods -l app=home-timeline-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$HOME_POD" ]; then
    echo "=== Step 3: Recent logs from $HOME_POD ==="
    kubectl logs "$HOME_POD" --tail=30 | grep -iE "error|fail|exception|zadd|redis" | tail -10 || echo "  (no errors in recent logs)"
    echo ""
    
    echo "=== Step 4: Testing Redis connectivity ==="
    kubectl exec "$HOME_POD" -- getent hosts home-timeline-redis 2>&1 || echo "  ✗ Cannot resolve home-timeline-redis"
    echo ""
else
    echo "=== Step 3: No running home-timeline-service pod found ==="
    echo "  Checking all pods (including failed ones)..."
    kubectl get pods -l app=home-timeline-service
    echo ""
fi

echo "=== Done ==="

