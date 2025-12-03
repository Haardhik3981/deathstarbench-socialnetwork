#!/bin/bash

# Verify what's actually in the pod and fix if needed

set -e

echo "=== Verifying resolver ==="
echo ""

POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD" ]; then
    echo "✗ No pod found"
    exit 1
fi

echo "Pod: $POD"
echo ""

# Check what resolver is in the pod
echo "Resolver line in pod:"
kubectl exec "$POD" -- cat /usr/local/openresty/nginx/conf/nginx.conf 2>/dev/null | grep "resolver" | grep -v "^#" | head -1

echo ""
echo "Checking if ConfigMap is mounted:"
kubectl exec "$POD" -- ls -la /usr/local/openresty/nginx/conf/nginx.conf 2>/dev/null

echo ""
echo "Checking what's in the ConfigMap:"
kubectl get configmap nginx-config -o jsonpath='{.data.nginx\.conf}' 2>/dev/null | grep "resolver" | grep -v "^#" | head -1

echo ""
echo "=== If resolver is still 127.0.0.11, the ConfigMap mount might not be working ==="
echo "Check the deployment to see how nginx.conf is mounted"

