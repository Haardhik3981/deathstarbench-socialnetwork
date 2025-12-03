#!/bin/bash

# Check social-graph-service status

set -e

echo "=== Checking social-graph-service ==="
echo ""

# Check pods
echo "=== Step 1: Checking pods ==="
kubectl get pods -l app=social-graph-service
echo ""

# Check service
echo "=== Step 2: Checking service ==="
kubectl get svc social-graph-service 2>&1 || echo "  ✗ Service not found"
echo ""

# Check logs
SOCIAL_POD=$(kubectl get pods -l app=social-graph-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SOCIAL_POD" ]; then
    echo "=== Step 3: Recent logs from $SOCIAL_POD ==="
    kubectl logs "$SOCIAL_POD" --tail=30 | tail -10
    echo ""
else
    echo "=== Step 3: No running social-graph-service pod found ==="
    kubectl get pods -l app=social-graph-service
    echo ""
fi

# Check write-home-timeline-service logs if it's crashing
WRITE_POD=$(kubectl get pods -l app=write-home-timeline-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$WRITE_POD" ]; then
    echo "=== Step 4: write-home-timeline-service logs (if crashing) ==="
    kubectl logs "$WRITE_POD" --tail=50 2>&1 | tail -20
    echo ""
fi

echo "=== Done ==="

