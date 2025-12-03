#!/bin/bash

# Check if fqdn_suffix is set in the pod

set -e

POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD" ]; then
    echo "✗ No pod found"
    exit 1
fi

echo "Pod: $POD"
echo ""
echo "=== Environment variables ==="
kubectl exec "$POD" -- env | grep -i fqdn || echo "  fqdn_suffix NOT SET!"

echo ""
echo "=== Checking deployment ==="
kubectl get deployment nginx-thrift-deployment -o yaml | grep -A 5 "env:" | head -10

