#!/bin/bash

# Quick fix for final issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=== Quick Fix: Final Issues ===${NC}"
echo ""

# Fix 1: Scale user-service to 1
echo -e "${BLUE}Fix 1: Scale user-service to 1 replica${NC}"
kubectl scale deployment user-service-deployment --replicas=1
echo "✓ Scaled"
sleep 3

# Fix 2: Check nginx-thrift logs
echo ""
echo -e "${BLUE}Fix 2: Check nginx-thrift logs${NC}"
NGINX_POD=$(kubectl get pods -l app=nginx-thrift | grep -v NAME | awk '{print $1}' | head -1)
echo "nginx-thrift pod: $NGINX_POD"
echo ""
echo "Recent logs (last 20 lines):"
kubectl logs "$NGINX_POD" --tail=20 2>&1 | tail -20 || echo "Could not get logs"
echo ""
echo "If it's still crashing, check the logs above for errors."

echo ""
echo -e "${BLUE}=== Final Status ===${NC}"
sleep 3
echo ""
echo "user-service pods:"
kubectl get pods -l app=user-service
echo ""
echo "nginx-thrift status:"
kubectl get pods -l app=nginx-thrift

