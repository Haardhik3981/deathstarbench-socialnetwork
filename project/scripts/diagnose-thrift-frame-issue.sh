#!/bin/bash

# Diagnose Thrift frame size issue

set -e

echo "=== Diagnosing Thrift Frame Issue ==="
echo ""

# Get pods
NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
USER_POD=$(kubectl get pods -l app=user-service --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$NGINX_POD" ]; then
    echo "✗ ERROR: No nginx-thrift pod found"
    exit 1
fi

if [ -z "$USER_POD" ]; then
    echo "✗ ERROR: No user-service pod found"
    exit 1
fi

echo "nginx-thrift pod: $NGINX_POD"
echo "user-service pod: $USER_POD"
echo ""

# Step 1: Check nginx-thrift logs for Thrift errors
echo "=== Step 1: Recent nginx-thrift logs (last 30 lines) ==="
kubectl logs "$NGINX_POD" --tail=30 2>&1 | tail -30
echo ""

# Step 2: Check for specific Thrift errors
echo "=== Step 2: Thrift-related errors in nginx-thrift ==="
kubectl logs "$NGINX_POD" --tail=100 2>&1 | grep -iE "thrift|frame|transport|protocol|user-service" | tail -10 || echo "  (no Thrift errors found)"
echo ""

# Step 3: Check user-service logs for frame errors
echo "=== Step 3: Recent user-service frame errors ==="
kubectl logs "$USER_POD" --tail=20 2>&1 | grep -E "frame|oversized" | tail -10 || echo "  (no frame errors in recent logs)"
echo ""

# Step 4: Make a test request and capture logs
echo "=== Step 4: Making test request and capturing logs ==="
echo ""
echo "Making request..."
echo ""

# Clear recent logs by getting current log position
NGINX_LOG_BEFORE=$(kubectl logs "$NGINX_POD" --tail=1 2>&1 | wc -l)
USER_LOG_BEFORE=$(kubectl logs "$USER_POD" --tail=1 2>&1 | wc -l)

# Make the request
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST http://localhost:8080/wrk2-api/user/register \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'user_id=99999&username=testuser&first_name=Test&last_name=User&password=test123' 2>&1)

HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v "HTTP_STATUS")

echo "Response Status: $HTTP_STATUS"
echo "Response Body:"
echo "$BODY" | head -5
echo ""

# Get new logs
echo "=== New nginx-thrift logs after request ==="
kubectl logs "$NGINX_POD" --tail=20 2>&1 | tail -20
echo ""

echo "=== New user-service logs after request ==="
kubectl logs "$USER_POD" --tail=20 2>&1 | tail -20
echo ""

# Step 5: Check if there's a frame size configuration
echo "=== Step 5: Checking for frame size configuration ==="
echo "Checking nginx-thrift config for frame size limits..."
kubectl exec "$NGINX_POD" -- sh -c 'grep -r "frame\|Frame\|FRAME" /usr/local/openresty/nginx/conf/ 2>/dev/null | head -5' || echo "  (no frame config found)"
echo ""

# Step 6: Summary and recommendations
echo "=== Summary ==="
echo ""
if [ "$HTTP_STATUS" = "500" ]; then
    echo "✗ Request failed with 500 error"
    echo ""
    echo "The 'Received an oversized frame' error suggests:"
    echo "  1. The Lua Thrift client may be sending frames in an incorrect format"
    echo "  2. There may be a frame size limit mismatch"
    echo "  3. The Thrift protocol version may be incompatible"
    echo ""
    echo "Next steps:"
    echo "  1. Check if the Lua Thrift library version matches the C++ Thrift version"
    echo "  2. Verify the TFramedTransport implementation is correct"
    echo "  3. Check if there are any frame size limits configured"
    echo "  4. Consider testing with a simple Thrift client to isolate the issue"
else
    echo "✓ Request succeeded (status: $HTTP_STATUS)"
fi

