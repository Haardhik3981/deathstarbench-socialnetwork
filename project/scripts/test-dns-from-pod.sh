#!/bin/bash

# Test DNS resolution from within the nginx-thrift pod

set -e

POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD" ]; then
    echo "✗ No pod found"
    exit 1
fi

echo "Pod: $POD"
echo ""
echo "=== /etc/resolv.conf ==="
kubectl exec "$POD" -- cat /etc/resolv.conf

echo ""
echo "=== Testing DNS resolution ==="
echo "Testing: user-service"
kubectl exec "$POD" -- getent hosts user-service 2>&1 || echo "  ✗ Failed"

echo ""
echo "Testing: user-service.default.svc.cluster.local"
kubectl exec "$POD" -- getent hosts user-service.default.svc.cluster.local 2>&1 || echo "  ✗ Failed"

echo ""
echo "=== Checking if user-service exists ==="
kubectl get svc user-service

