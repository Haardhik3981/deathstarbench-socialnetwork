#!/bin/bash

# Get the actual error from nginx-thrift right now

set -e

echo "=== Getting nginx-thrift error ==="
echo ""

NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$NGINX_POD" ]; then
    echo "✗ No nginx-thrift pod found"
    exit 1
fi

echo "Pod: $NGINX_POD"
echo ""
echo "=== Recent logs (last 30 lines) ==="
kubectl logs "$NGINX_POD" --tail=30
echo ""
echo "=== Errors only ==="
kubectl logs "$NGINX_POD" --tail=100 | grep -iE "error|fail|exception" | tail -10 || echo "  (no errors found)"

