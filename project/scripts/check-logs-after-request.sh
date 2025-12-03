#!/bin/bash

# Check logs immediately after making a request

set -e

echo "=== Checking nginx-thrift logs after request ==="
echo ""

NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$NGINX_POD" ]; then
    echo "✗ No nginx-thrift pod found"
    exit 1
fi

echo "Pod: $NGINX_POD"
echo ""
echo "=== Last 50 lines of logs ==="
kubectl logs "$NGINX_POD" --tail=50
echo ""
echo "=== Checking for errors ==="
kubectl logs "$NGINX_POD" --tail=100 | grep -iE "error|fail|exception|warn" | tail -20 || echo "  (no errors found)"
echo ""
echo "=== Checking pod status ==="
kubectl get pod "$NGINX_POD" -o wide

