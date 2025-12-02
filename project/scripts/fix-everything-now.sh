#!/bin/bash
# Fix everything right now

echo "=== Fixing Everything ==="
echo ""

# 1. Scale nginx to 1
echo "1. Scaling nginx-thrift to 1 replica..."
kubectl scale deployment nginx-thrift-deployment --replicas=1

# 2. Scale user-service to 1  
echo "2. Scaling user-service to 1 replica..."
kubectl scale deployment user-service-deployment --replicas=1

# 3. Wait
echo "3. Waiting 5 seconds..."
sleep 5

# 4. Check status
echo ""
echo "=== Status ==="
kubectl get pods -l app=nginx-thrift
kubectl get pods -l app=user-service

echo ""
echo "If nginx is still restarting, check logs:"
echo "  kubectl logs <nginx-pod-name>"

