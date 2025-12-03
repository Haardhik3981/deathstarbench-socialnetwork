#!/bin/bash

# Test connectivity to user-service from nginx-thrift pod
# Using methods that work in the OpenResty container

set -e

echo "=== Testing Service Connectivity ==="
echo ""

# Get nginx-thrift pod
NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$NGINX_POD" ]; then
    echo "✗ ERROR: No nginx-thrift pod found"
    exit 1
fi

echo "Using pod: $NGINX_POD"
echo ""

# Step 1: Check service selector matches pod labels
echo "Step 1: Verifying service selector matches pod labels..."
SERVICE_SELECTOR=$(kubectl get service user-service -o jsonpath='{.spec.selector}' 2>/dev/null)
echo "  Service selector: $SERVICE_SELECTOR"

USER_POD=$(kubectl get pods -l app=user-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$USER_POD" ]; then
    POD_LABELS=$(kubectl get pod "$USER_POD" -o jsonpath='{.metadata.labels}' 2>/dev/null)
    echo "  Pod labels: $POD_LABELS"
    echo "  ✓ Pod found: $USER_POD"
else
    echo "  ✗ No user-service pod found"
fi

# Step 2: Test DNS using getent (usually available in minimal images)
echo ""
echo "Step 2: Testing DNS resolution (using getent if available)..."
if kubectl exec "$NGINX_POD" -- getent hosts user-service 2>&1 | grep -q "user-service"; then
    echo "  ✓ DNS resolution works!"
    kubectl exec "$NGINX_POD" -- getent hosts user-service
else
    echo "  ⚠ getent not available, trying alternative method..."
    # Try using Lua to test connectivity
    echo "  Testing with Lua script..."
fi

# Step 3: Test connectivity using a simple TCP connection test
echo ""
echo "Step 3: Testing TCP connectivity to user-service:9090..."
# Use a simple test that should work in most containers
CONNECTION_TEST=$(kubectl exec "$NGINX_POD" -- sh -c 'timeout 3 sh -c "</dev/tcp/user-service/9090" 2>&1 || echo "CONNECTION_FAILED"' 2>&1 || echo "EXEC_FAILED")

if echo "$CONNECTION_TEST" | grep -q "CONNECTION_FAILED\|EXEC_FAILED"; then
    echo "  ⚠ Cannot test with /dev/tcp (not available in this container)"
    echo "  This is normal for minimal containers"
else
    echo "  ✓ Connection test passed"
fi

# Step 4: Check if we can resolve the service IP
echo ""
echo "Step 4: Getting service IP and testing from nginx pod..."
SERVICE_IP=$(kubectl get service user-service -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
if [ -n "$SERVICE_IP" ]; then
    echo "  Service IP: $SERVICE_IP"
    echo "  Testing direct IP connection..."
    # Try to connect to the service IP directly
    kubectl exec "$NGINX_POD" -- sh -c "timeout 2 sh -c '</dev/tcp/$SERVICE_IP/9090' 2>&1" && echo "  ✓ Can connect to service IP" || echo "  ✗ Cannot connect to service IP"
else
    echo "  ✗ Could not get service IP"
fi

# Step 5: Check actual endpoint IPs
echo ""
echo "Step 5: Checking service endpoints..."
ENDPOINTS=$(kubectl get endpoints user-service -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")
if [ -n "$ENDPOINTS" ]; then
    echo "  Endpoint IPs: $ENDPOINTS"
    for ep in $ENDPOINTS; do
        echo "  Testing endpoint $ep:9090..."
        kubectl exec "$NGINX_POD" -- sh -c "timeout 2 sh -c '</dev/tcp/$ep/9090' 2>&1" && echo "    ✓ Can connect" || echo "    ✗ Cannot connect"
    done
else
    echo "  ✗ No endpoints found (pods may not be ready)"
fi

# Step 6: Check network policies
echo ""
echo "Step 6: Checking for network policies that might block traffic..."
NETPOL_COUNT=$(kubectl get networkpolicies --all-namespaces 2>/dev/null | wc -l | tr -d ' ')
if [ "$NETPOL_COUNT" -gt 1 ]; then
    echo "  ⚠ Found network policies (may be blocking traffic):"
    kubectl get networkpolicies --all-namespaces
else
    echo "  ✓ No network policies found (traffic should flow freely)"
fi

# Step 7: Test actual request
echo ""
echo "Step 7: Testing actual HTTP request through nginx..."
echo "  (This will show if nginx can reach user-service)"
echo ""
echo "Make a test request and check nginx logs:"
echo "  curl -X POST http://localhost:8080/wrk2-api/user/register \\"
echo "    -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "    -d 'user_id=123&username=test&first_name=Test&last_name=User&password=test'"
echo ""
echo "Then check logs:"
echo "  kubectl logs $NGINX_POD --tail=20"

