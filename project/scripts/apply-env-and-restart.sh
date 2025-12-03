#!/bin/bash

# Apply deployment and restart pod to get fqdn_suffix

set -e

echo "=== Applying deployment with fqdn_suffix ==="
echo ""

# Apply the deployment
kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml

echo "✓ Deployment applied"
echo ""

# Restart pod
echo "Restarting pod..."
kubectl delete pod -l app=nginx-thrift
echo "Waiting for pod..."
sleep 15
kubectl wait --for=condition=ready pod -l app=nginx-thrift --timeout=60s || true

# Verify
NEW_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NEW_POD" ]; then
    echo ""
    echo "Verifying fqdn_suffix in pod $NEW_POD..."
    FQDN_SUFFIX=$(kubectl exec "$NEW_POD" -- sh -c 'echo $fqdn_suffix' 2>/dev/null || echo "")
    if [ -n "$FQDN_SUFFIX" ]; then
        echo "✓ fqdn_suffix is set: $FQDN_SUFFIX"
    else
        echo "✗ fqdn_suffix is NOT set"
        echo "Checking deployment..."
        kubectl get deployment nginx-thrift-deployment -o yaml | grep -A 3 "env:" | head -5
    fi
fi

echo ""
echo "=== Done ==="

