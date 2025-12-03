#!/bin/bash

# Fix compose-post errors by checking and fixing social-graph-service

set -e

echo "=== Fixing Compose Post Errors ==="
echo ""

# Step 1: Check social-graph-service
echo "=== Step 1: Checking social-graph-service ==="
SOCIAL_PODS=$(kubectl get pods -l app=social-graph-service --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$SOCIAL_PODS" -eq 0 ]; then
    echo "✗ social-graph-service is NOT deployed!"
    echo ""
    echo "You need to deploy social-graph-service. Check if you have:"
    echo "  - kubernetes/deployments/social-graph-service-deployment.yaml"
    echo "  - kubernetes/services/social-graph-service.yaml (or in all-microservices.yaml)"
    echo ""
    exit 1
else
    echo "✓ social-graph-service pods found: $SOCIAL_PODS"
    kubectl get pods -l app=social-graph-service
    echo ""
fi

# Step 2: Check if service is running
SOCIAL_RUNNING=$(kubectl get pods -l app=social-graph-service --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$SOCIAL_RUNNING" -eq 0 ]; then
    echo "⚠ social-graph-service pods are NOT running!"
    echo "Checking pod status..."
    kubectl get pods -l app=social-graph-service
    echo ""
    echo "Check logs with:"
    echo "  kubectl logs -l app=social-graph-service --tail=50"
    echo ""
else
    echo "✓ social-graph-service is running"
    echo ""
fi

# Step 3: Check service exists
echo "=== Step 2: Checking social-graph-service service ==="
if kubectl get svc social-graph-service &>/dev/null; then
    echo "✓ social-graph-service service exists"
    kubectl get svc social-graph-service
    echo ""
else
    echo "✗ social-graph-service service NOT found!"
    echo "You need to create the service. Check:"
    echo "  - kubernetes/services/all-microservices.yaml"
    echo "  - Or create: kubernetes/services/social-graph-service.yaml"
    echo ""
fi

# Step 4: Test connectivity from home-timeline-service
echo "=== Step 3: Testing connectivity ==="
HOME_POD=$(kubectl get pods -l app=home-timeline-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$HOME_POD" ]; then
    echo "Testing DNS resolution from home-timeline-service pod:"
    kubectl exec "$HOME_POD" -- getent hosts social-graph-service 2>&1 || echo "  ✗ Cannot resolve social-graph-service"
    echo ""
else
    echo "⚠ home-timeline-service pod not found for connectivity test"
    echo ""
fi

# Step 5: Check write-home-timeline-service (optional)
echo "=== Step 4: Checking write-home-timeline-service (optional) ==="
WRITE_POD=$(kubectl get pods -l app=write-home-timeline-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$WRITE_POD" ]; then
    WRITE_STATUS=$(kubectl get pod "$WRITE_POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$WRITE_STATUS" != "Running" ]; then
        echo "⚠ write-home-timeline-service is $WRITE_STATUS"
        echo "Recent logs:"
        kubectl logs "$WRITE_POD" --tail=20 2>&1 | tail -10
        echo ""
    else
        echo "✓ write-home-timeline-service is running"
        echo ""
    fi
else
    echo "ℹ write-home-timeline-service not deployed (optional)"
    echo ""
fi

echo "=== Summary ==="
echo ""
echo "The main issue is that social-graph-service must be running and accessible."
echo "Once that's fixed, the 'Failed to get followers' error should be resolved."
echo ""
echo "Next steps:"
echo "1. Ensure social-graph-service is deployed and running"
echo "2. Restart home-timeline-service: kubectl rollout restart deployment/home-timeline-service-deployment"
echo "3. Restart compose-post-service: kubectl rollout restart deployment/compose-post-service-deployment"
echo "4. Run your k6 test again"

