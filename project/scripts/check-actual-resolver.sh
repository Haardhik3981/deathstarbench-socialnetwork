#!/bin/bash

# Check what resolver is actually in the pod

set -e

POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD" ]; then
    echo "✗ No pod found"
    exit 1
fi

echo "Pod: $POD"
echo ""
echo "=== All resolver lines (including comments) ==="
kubectl exec "$POD" -- cat /usr/local/openresty/nginx/conf/nginx.conf 2>/dev/null | grep -i resolver

echo ""
echo "=== Actual resolver line (not comments) ==="
kubectl exec "$POD" -- cat /usr/local/openresty/nginx/conf/nginx.conf 2>/dev/null | grep "^[^#]*resolver" | head -1

echo ""
echo "=== What's in the ConfigMap ==="
kubectl get configmap deathstarbench-config -o jsonpath='{.data.nginx\.conf}' 2>/dev/null | grep "^[^#]*resolver" | head -1

