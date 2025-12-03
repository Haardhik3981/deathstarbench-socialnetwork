#!/bin/bash

# Fix pod and port-forward issues
# This addresses the common problem of old pods or stale port-forwards

set -e

echo "=== Fixing Pod and Port-Forward Issues ==="
echo ""

# Step 1: Check current pod status
echo "Step 1: Checking pod status..."
kubectl get pods -l app=nginx-thrift

echo ""
echo "Step 2: Identifying old vs new pods..."

# Get all pods with their creation times
ALL_PODS=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.creationTimestamp}{"|"}{.status.phase}{"\n"}{end}')

if [ -z "$ALL_PODS" ]; then
    echo "✗ ERROR: No pods found!"
    exit 1
fi

# Find the newest running pod
NEWEST_POD=$(echo "$ALL_PODS" | grep "Running" | sort -t'|' -k2 -r | head -1 | cut -d'|' -f1)

if [ -z "$NEWEST_POD" ]; then
    echo "✗ ERROR: No running pod found!"
    echo ""
    echo "All pods:"
    echo "$ALL_PODS"
    exit 1
fi

echo "✓ Newest running pod: $NEWEST_POD"

# Find old pods (not the newest one)
OLD_PODS=$(echo "$ALL_PODS" | grep -v "^$NEWEST_POD|" | cut -d'|' -f1 | grep -v "^$" || echo "")

if [ -n "$OLD_PODS" ]; then
    echo ""
    echo "⚠ Found old pods that should be cleaned up:"
    for pod in $OLD_PODS; do
        PHASE=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")
        echo "  - $pod (phase: $PHASE)"
    done
    
    echo ""
    echo "Step 3: Cleaning up old pods..."
    for pod in $OLD_PODS; do
        echo "  Deleting $pod..."
        kubectl delete pod "$pod" --grace-period=0 --force 2>&1 || true
    done
    echo "✓ Old pods deleted"
else
    echo "✓ No old pods found"
fi

# Step 4: Verify service endpoints
echo ""
echo "Step 4: Checking service endpoints..."
SERVICE_ENDPOINTS=$(kubectl get endpoints nginx-thrift-service -o jsonpath='{.subsets[0].addresses[*].targetRef.name}' 2>/dev/null || echo "")

if [ -z "$SERVICE_ENDPOINTS" ]; then
    echo "⚠ Service has no endpoints (pod may not be ready)"
else
    echo "Service endpoints:"
    for endpoint in $SERVICE_ENDPOINTS; do
        if [ "$endpoint" = "$NEWEST_POD" ]; then
            echo "  ✓ $endpoint (correct)"
        else
            echo "  ⚠ $endpoint (may be old pod)"
        fi
    done
fi

# Step 5: Check if port-forward is running
echo ""
echo "Step 5: Checking port-forward..."
PF_PROCESS=$(lsof -ti:8080 2>/dev/null || echo "")

if [ -n "$PF_PROCESS" ]; then
    echo "⚠ Port-forward process found on port 8080 (PID: $PF_PROCESS)"
    echo "  This may be pointing to an old pod"
    echo ""
    echo "  To fix:"
    echo "  1. Kill the old port-forward: kill $PF_PROCESS"
    echo "  2. Start a new one: kubectl port-forward svc/nginx-thrift-service 8080:8080"
    echo ""
    read -p "  Kill old port-forward and start new one? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "  Killing old port-forward..."
        kill $PF_PROCESS 2>/dev/null || true
        sleep 2
        echo "  Starting new port-forward in background..."
        kubectl port-forward svc/nginx-thrift-service 8080:8080 > /tmp/port-forward.log 2>&1 &
        PF_NEW_PID=$!
        sleep 2
        if kill -0 $PF_NEW_PID 2>/dev/null; then
            echo "  ✓ Port-forward started (PID: $PF_NEW_PID)"
            echo "  Logs: /tmp/port-forward.log"
        else
            echo "  ✗ Port-forward failed to start"
            echo "  Check logs: cat /tmp/port-forward.log"
        fi
    fi
else
    echo "  No port-forward found on port 8080"
    echo "  Start one with: kubectl port-forward svc/nginx-thrift-service 8080:8080"
fi

# Step 6: Verify pod is ready
echo ""
echo "Step 6: Verifying pod is ready..."
READY=$(kubectl get pod "$NEWEST_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

if [ "$READY" = "true" ]; then
    echo "✓ Pod $NEWEST_POD is ready"
else
    echo "⚠ Pod $NEWEST_POD is not ready yet"
    echo "  Checking status:"
    kubectl get pod "$NEWEST_POD" -o jsonpath='  Phase: {.status.phase}{"\n"}'
    kubectl get pod "$NEWEST_POD" -o jsonpath='  Ready: {.status.containerStatuses[0].ready}{"\n"}'
    kubectl get pod "$NEWEST_POD" -o jsonpath='  Restarts: {.status.containerStatuses[0].restartCount}{"\n"}'
    
    echo ""
    echo "  Recent events:"
    kubectl get events --field-selector involvedObject.name=$NEWEST_POD --sort-by='.lastTimestamp' | tail -5
fi

# Step 7: Test connectivity
echo ""
echo "Step 7: Testing connectivity..."
sleep 2

if curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8080/ > /tmp/curl-test.txt 2>&1; then
    HTTP_CODE=$(cat /tmp/curl-test.txt)
    if [ "$HTTP_CODE" != "000" ]; then
        echo "✓ Connection successful (HTTP $HTTP_CODE)"
    else
        echo "✗ Connection failed (status 000 - connection refused)"
        echo "  This usually means:"
        echo "    - Port-forward is not running or pointing to wrong pod"
        echo "    - Pod is not ready"
        echo "    - Service endpoints are not updated"
    fi
else
    echo "✗ Connection test failed"
    echo "  Error: $(cat /tmp/curl-test.txt)"
fi

echo ""
echo "=== Summary ==="
echo ""
echo "Current pod: $NEWEST_POD"
echo "Pod ready: $READY"
if [ -n "$PF_PROCESS" ]; then
    echo "Port-forward: Running (PID: $PF_PROCESS) - may need restart"
else
    echo "Port-forward: Not running - start with: kubectl port-forward svc/nginx-thrift-service 8080:8080"
fi
echo ""
echo "Next steps:"
echo "1. If port-forward needs restart, kill old one and start new:"
echo "   pkill -f 'port-forward.*8080'"
echo "   kubectl port-forward svc/nginx-thrift-service 8080:8080 &"
echo ""
echo "2. Test endpoint:"
echo "   ./k6-tests/test-endpoint.sh"
echo ""
echo "3. Check pod logs if still having issues:"
echo "   kubectl logs $NEWEST_POD --tail=50"

