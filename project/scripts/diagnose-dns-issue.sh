#!/bin/bash

# Diagnose the DNS resolution issue

set -e

echo "=== Diagnosing DNS/Connectivity Issue ==="
echo ""

# Get pods
NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$NGINX_POD" ]; then
    echo "✗ No nginx-thrift pod found"
    exit 1
fi

echo "Using nginx-thrift pod: $NGINX_POD"
echo ""

# Step 1: Check environment variables
echo "Step 1: Checking environment variables in nginx-thrift pod..."
FQDN_SUFFIX=$(kubectl exec "$NGINX_POD" -- sh -c 'echo $fqdn_suffix' 2>/dev/null || echo "")
if [ -n "$FQDN_SUFFIX" ]; then
    echo "  fqdn_suffix = '$FQDN_SUFFIX'"
    echo "  → Will try to connect to: user-service$FQDN_SUFFIX"
else
    echo "  fqdn_suffix = (not set)"
    echo "  → Will try to connect to: user-service"
fi

# Step 2: Check /etc/resolv.conf (DNS configuration)
echo ""
echo "Step 2: Checking DNS configuration..."
kubectl exec "$NGINX_POD" -- cat /etc/resolv.conf 2>/dev/null || echo "  (cannot read resolv.conf)"

# Step 3: Test DNS using getent (if available) or ping
echo ""
echo "Step 3: Testing DNS resolution..."
if kubectl exec "$NGINX_POD" -- which getent >/dev/null 2>&1; then
    echo "  Using getent..."
    kubectl exec "$NGINX_POD" -- getent hosts user-service 2>&1 || echo "  ✗ DNS resolution failed"
elif kubectl exec "$NGINX_POD" -- which ping >/dev/null 2>&1; then
    echo "  Using ping..."
    kubectl exec "$NGINX_POD" -- ping -c 1 user-service 2>&1 | head -3 || echo "  ✗ DNS resolution failed"
else
    echo "  ⚠ No DNS tools available in container"
fi

# Step 4: Get service IP and test direct connection
echo ""
echo "Step 4: Testing direct IP connection..."
SERVICE_IP=$(kubectl get service user-service -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
if [ -n "$SERVICE_IP" ]; then
    echo "  Service IP: $SERVICE_IP"
    echo "  Testing connection..."
    # Try a simple connection test
    if kubectl exec "$NGINX_POD" -- sh -c "timeout 3 sh -c 'exec 3<>/dev/tcp/$SERVICE_IP/9090 && echo >&3 && cat <&3' 2>&1" | head -1; then
        echo "  ✓ Can connect to service IP"
    else
        echo "  ✗ Cannot connect to service IP"
        echo "  This suggests a network connectivity issue, not DNS"
    fi
fi

# Step 5: Check endpoint IPs
echo ""
echo "Step 5: Testing endpoint IPs directly..."
ENDPOINTS=$(kubectl get endpoints user-service -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || echo "")
if [ -n "$ENDPOINTS" ]; then
    echo "  Endpoint IPs: $ENDPOINTS"
    for ep in $ENDPOINTS; do
        echo "  Testing $ep:9090..."
        if kubectl exec "$NGINX_POD" -- sh -c "timeout 2 sh -c 'exec 3<>/dev/tcp/$ep/9090 && echo >&3' 2>&1"; then
            echo "    ✓ Can connect"
        else
            echo "    ✗ Cannot connect"
        fi
    done
else
    echo "  ✗ No endpoints found"
fi

# Step 6: Check if user-service pods are actually listening
echo ""
echo "Step 6: Checking if user-service pods are listening on port 9090..."
USER_PODS=$(kubectl get pods -l app=user-service --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$USER_PODS" ]; then
    for pod in $USER_PODS; do
        echo "  Checking pod: $pod"
        # Check if port 9090 is listening
        LISTENING=$(kubectl exec "$pod" -- sh -c 'netstat -tln 2>/dev/null | grep 9090 || ss -tln 2>/dev/null | grep 9090 || echo "NO_TOOLS"' 2>&1 || echo "ERROR")
        if echo "$LISTENING" | grep -q "9090"; then
            echo "    ✓ Port 9090 is listening"
        elif echo "$LISTENING" | grep -q "NO_TOOLS"; then
            echo "    ⚠ Cannot check (no netstat/ss available)"
        else
            echo "    ✗ Port 9090 may not be listening"
            echo "    Pod logs:"
            kubectl logs "$pod" --tail=5 2>&1 | head -3
        fi
    done
else
    echo "  ✗ No user-service pods found"
fi

# Step 7: Check recent nginx logs for more details
echo ""
echo "Step 7: Recent nginx-thrift logs (last 10 lines)..."
kubectl logs "$NGINX_POD" --tail=10 2>&1 | grep -E "error|fail|user-service|9090" || kubectl logs "$NGINX_POD" --tail=10

echo ""
echo "=== Summary ==="
echo ""
echo "If DNS resolution is failing but service exists:"
echo "  1. Check if CoreDNS is running: kubectl get pods -n kube-system | grep coredns"
echo "  2. Check network policies: kubectl get networkpolicies"
echo "  3. Try using full DNS name: user-service.default.svc.cluster.local"
echo ""
echo "If connectivity to IP works but DNS doesn't:"
echo "  → DNS issue (CoreDNS problem or network policy)"
echo ""
echo "If connectivity to IP also fails:"
echo "  → Network policy or firewall blocking traffic"

