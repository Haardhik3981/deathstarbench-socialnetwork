#!/bin/bash

# Start port-forward and test the endpoint

set -e

echo "=== Starting Port-Forward and Testing ==="
echo ""

# Step 1: Kill any existing port-forwards
echo "Step 1: Cleaning up old port-forwards..."
pkill -f 'port-forward.*8080' 2>/dev/null && echo "  ✓ Killed old port-forward" || echo "  (none found)"
sleep 1

# Step 2: Get the current pod
POD_NAME=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    echo "✗ ERROR: No running pod found!"
    kubectl get pods -l app=nginx-thrift
    exit 1
fi

echo "✓ Using pod: $POD_NAME"

# Step 3: Check pod logs for errors
echo ""
echo "Step 2: Checking pod logs for errors..."
RECENT_LOGS=$(kubectl logs "$POD_NAME" --tail=20 2>&1)

if echo "$RECENT_LOGS" | grep -qi "error\|fail\|cannot\|not found"; then
    echo "⚠ Found potential errors in logs:"
    echo "$RECENT_LOGS" | grep -i "error\|fail\|cannot\|not found" | head -5
else
    echo "✓ No obvious errors in recent logs"
fi

# Step 4: Start port-forward
echo ""
echo "Step 3: Starting port-forward..."
echo "  Command: kubectl port-forward svc/nginx-thrift-service 8080:8080"
echo "  (This will run in the background)"

# Start port-forward in background
kubectl port-forward svc/nginx-thrift-service 8080:8080 > /tmp/port-forward.log 2>&1 &
PF_PID=$!

# Wait a moment for it to start
sleep 3

# Check if it's still running
if kill -0 $PF_PID 2>/dev/null; then
    echo "  ✓ Port-forward started (PID: $PF_PID)"
    echo "  Logs: /tmp/port-forward.log"
else
    echo "  ✗ Port-forward failed to start"
    echo "  Error log:"
    cat /tmp/port-forward.log
    exit 1
fi

# Step 5: Test connectivity
echo ""
echo "Step 4: Testing connectivity..."
sleep 2

# Test basic connectivity
if curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8080/ > /tmp/curl-test.txt 2>&1; then
    HTTP_CODE=$(cat /tmp/curl-test.txt)
    if [ "$HTTP_CODE" != "000" ] && [ -n "$HTTP_CODE" ]; then
        echo "✓ Connection successful (HTTP $HTTP_CODE)"
    else
        echo "✗ Connection failed (status: $HTTP_CODE)"
        echo "  This might mean the pod isn't responding"
    fi
else
    echo "✗ Connection test failed"
    echo "  Error: $(cat /tmp/curl-test.txt)"
fi

# Step 6: Test the actual endpoint
echo ""
echo "Step 5: Testing wrk2-api/user/register endpoint..."
TEST_RESULT=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST http://localhost:8080/wrk2-api/user/register \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "user_id=99999&username=testuser&first_name=Test&last_name=User&password=testpass123" \
  --max-time 10 2>&1)

HTTP_STATUS=$(echo "$TEST_RESULT" | grep "HTTP_STATUS:" | cut -d: -f2)
BODY=$(echo "$TEST_RESULT" | sed '/HTTP_STATUS:/d')

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✓ SUCCESS! Endpoint returned 200"
    echo "  Response: $BODY"
elif [ "$HTTP_STATUS" = "000" ]; then
    echo "✗ Connection refused (status 000)"
    echo "  Port-forward may not be working correctly"
    echo "  Check: cat /tmp/port-forward.log"
elif [ -n "$HTTP_STATUS" ]; then
    echo "⚠ Endpoint returned HTTP $HTTP_STATUS"
    echo "  Response: $BODY"
    echo "  This is progress! The connection works, but there may be an application error"
else
    echo "✗ Failed to get response"
    echo "  Full output: $TEST_RESULT"
fi

echo ""
echo "=== Summary ==="
echo ""
echo "Port-forward PID: $PF_PID"
echo "Port-forward log: /tmp/port-forward.log"
echo ""
echo "To stop port-forward: kill $PF_PID"
echo ""
echo "To test endpoint: ./k6-tests/test-endpoint.sh"
echo ""
echo "If you see errors, check:"
echo "  - Port-forward log: cat /tmp/port-forward.log"
echo "  - Pod logs: kubectl logs $POD_NAME --tail=50"
echo "  - Pod status: kubectl get pod $POD_NAME"

