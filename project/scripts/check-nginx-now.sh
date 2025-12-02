#!/bin/bash
# Quick check of nginx issues

echo "=== Checking nginx-thrift pods ==="
kubectl get pods -l app=nginx-thrift

echo ""
echo "=== Recent logs from first pod ==="
NGINX_POD=$(kubectl get pods -l app=nginx-thrift | grep -v NAME | head -1 | awk '{print $1}')
if [ -n "$NGINX_POD" ]; then
    echo "Pod: $NGINX_POD"
    kubectl logs "$NGINX_POD" --tail=30
fi

echo ""
echo "=== Pod events ==="
kubectl describe pod "$NGINX_POD" | grep -A 10 "Events:" | head -15

