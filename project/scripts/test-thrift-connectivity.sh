#!/bin/bash

# Test Thrift connectivity and check user-service status

set -e

echo "=== Testing Thrift Connectivity ==="
echo ""

# Get pods
NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
USER_PODS=($(kubectl get pods -l app=user-service --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""))

echo "nginx-thrift pod: $NGINX_POD"
echo "user-service pods: ${USER_PODS[@]}"
echo ""

# Step 1: Check user-service pod logs for connection attempts
echo "Step 1: Checking user-service logs for connection attempts..."
if [ ${#USER_PODS[@]} -gt 0 ]; then
    for pod in "${USER_PODS[@]}"; do
        echo "  Pod: $pod"
        echo "  Recent logs:"
        kubectl logs "$pod" --tail=10 2>&1 | grep -E "connection|connect|request|error" | head -5 || echo "    (no relevant logs)"
        echo ""
    done
else
    echo "  ✗ No user-service pods found"
fi

# Step 2: Check if user-service is actually ready
echo "Step 2: Checking user-service pod readiness..."
for pod in "${USER_PODS[@]}"; do
    READY=$(kubectl get pod "$pod" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    RESTARTS=$(kubectl get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    echo "  $pod: Ready=$READY, Restarts=$RESTARTS"
    
    if [ "$RESTARTS" -gt 0 ]; then
        echo "    ⚠ Pod has restarted $RESTARTS times - may be crashing"
        echo "    Recent events:"
        kubectl get events --field-selector involvedObject.name=$pod --sort-by='.lastTimestamp' | tail -3
    fi
done

# Step 3: Test using Lua/OpenResty tools (if available)
echo ""
echo "Step 3: Testing connectivity using methods available in OpenResty..."
SERVICE_IP=$(kubectl get service user-service -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -n "$SERVICE_IP" ]; then
    echo "  Service IP: $SERVICE_IP"
    echo "  Testing with Lua socket (if available)..."
    
    # Try to use Lua to test connection
    LUA_TEST=$(kubectl exec "$NGINX_POD" -- sh -c 'lua -e "local socket = require(\"socket\"); local t = socket.tcp(); t:settimeout(2); local ok, err = t:connect(\"user-service\", 9090); if ok then print(\"SUCCESS\"); t:close(); else print(\"FAILED: \" .. tostring(err)); end"' 2>&1 || echo "LUA_NOT_AVAILABLE")
    
    if echo "$LUA_TEST" | grep -q "SUCCESS"; then
        echo "  ✓ Can connect using Lua socket"
    elif echo "$LUA_TEST" | grep -q "FAILED"; then
        echo "  ✗ Connection failed: $LUA_TEST"
    else
        echo "  ⚠ Lua socket test not available or failed"
    fi
fi

# Step 4: Check network policies
echo ""
echo "Step 4: Checking for network policies..."
NETPOL=$(kubectl get networkpolicies --all-namespaces 2>/dev/null | wc -l | tr -d ' ')
if [ "$NETPOL" -gt 1 ]; then
    echo "  ⚠ Found network policies (may be blocking traffic):"
    kubectl get networkpolicies --all-namespaces
else
    echo "  ✓ No network policies found"
fi

# Step 5: Check if user-service is actually processing requests
echo ""
echo "Step 5: Making a test request and checking logs..."
echo "  (This will show if nginx can reach user-service)"
echo ""
echo "Make a request:"
echo "  curl -X POST http://localhost:8080/wrk2-api/user/register \\"
echo "    -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "    -d 'user_id=99999&username=testuser&first_name=Test&last_name=User&password=test123'"
echo ""
echo "Then immediately check logs:"
echo "  kubectl logs $NGINX_POD --tail=20 | grep -E 'user-service|error|fail'"
echo ""
echo "And check user-service logs:"
if [ ${#USER_PODS[@]} -gt 0 ]; then
    echo "  kubectl logs ${USER_PODS[0]} --tail=20"
fi

# Step 6: Check if there's a Thrift protocol mismatch
echo ""
echo "Step 6: Checking Thrift client configuration..."
echo "  The Lua script uses: GenericObjectPool:connection(UserServiceClient, \"user-service\", 9090)"
echo "  This should work if:"
echo "    1. DNS resolves (✓ confirmed working)"
echo "    2. Port 9090 is open (need to verify)"
echo "    3. Thrift protocol matches (need to verify)"
echo ""
echo "  The timeout error suggests the Thrift client can't establish a connection."
echo "  This could mean:"
echo "    - user-service pods aren't actually listening on 9090"
echo "    - Network policy is blocking traffic"
echo "    - Thrift protocol version mismatch"

