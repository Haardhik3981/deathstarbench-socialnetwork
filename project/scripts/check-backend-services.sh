#!/bin/bash

# Check if backend microservices are deployed and accessible

set -e

echo "=== Checking Backend Microservices ==="
echo ""
echo "The nginx-thrift gateway needs to connect to backend services like:"
echo "  - user-service:9090"
echo "  - compose-post-service:9090"
echo "  - social-graph-service:9090"
echo "  - etc."
echo ""

# Check if user-service exists
echo "Step 1: Checking user-service..."
if kubectl get service user-service >/dev/null 2>&1; then
    echo "✓ user-service exists"
    kubectl get service user-service
    echo ""
    echo "  Endpoints:"
    kubectl get endpoints user-service
else
    echo "✗ user-service NOT FOUND"
    echo ""
    echo "  Available services:"
    kubectl get services | grep -E "NAME|service" || kubectl get services | head -10
fi

# Check if user-service pods are running
echo ""
echo "Step 2: Checking user-service pods..."
if kubectl get pods -l app=user-service 2>/dev/null | grep -q "Running"; then
    echo "✓ user-service pods are running:"
    kubectl get pods -l app=user-service
else
    echo "✗ No running user-service pods found"
    echo ""
    echo "  All pods with 'user' in name:"
    kubectl get pods | grep -i user || echo "  (none found)"
fi

# Check DNS resolution from nginx-thrift pod
echo ""
echo "Step 3: Testing DNS resolution from nginx-thrift pod..."
NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$NGINX_POD" ]; then
    echo "  Using pod: $NGINX_POD"
    echo ""
    echo "  Testing DNS resolution for 'user-service':"
    if kubectl exec "$NGINX_POD" -- nslookup user-service 2>&1 | grep -q "Name:"; then
        echo "  ✓ DNS resolution works"
        kubectl exec "$NGINX_POD" -- nslookup user-service 2>&1 | grep -A 2 "Name:"
    else
        echo "  ✗ DNS resolution FAILED"
        echo "  Full output:"
        kubectl exec "$NGINX_POD" -- nslookup user-service 2>&1 || true
    fi
    
    echo ""
    echo "  Testing connectivity to user-service:9090:"
    if kubectl exec "$NGINX_POD" -- nc -zv user-service 9090 2>&1 | grep -q "succeeded\|open"; then
        echo "  ✓ Can connect to user-service:9090"
    else
        echo "  ✗ Cannot connect to user-service:9090"
        echo "  Full output:"
        kubectl exec "$NGINX_POD" -- nc -zv user-service 9090 2>&1 || echo "  (nc may not be installed, trying telnet...)"
        kubectl exec "$NGINX_POD" -- sh -c "echo > /dev/tcp/user-service/9090" 2>&1 && echo "  ✓ Connection test passed" || echo "  ✗ Connection test failed"
    fi
else
    echo "  ✗ No nginx-thrift pod found"
fi

# List all services to see what's available
echo ""
echo "Step 4: All services in cluster:"
kubectl get services | head -20

echo ""
echo "=== Summary ==="
echo ""
echo "For the social network to work, you need these services deployed:"
echo "  - user-service (for user registration, login)"
echo "  - compose-post-service (for creating posts)"
echo "  - social-graph-service (for following users)"
echo "  - home-timeline-service (for reading timelines)"
echo "  - And more..."
echo ""
echo "If services are missing, you need to deploy them."
echo "Check your deployment scripts or helm charts."

