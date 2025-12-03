#!/bin/bash

# Check user-service status and logs

set -e

echo "=== Checking User-Service Status ==="
echo ""

# Get user-service pods
USER_PODS=($(kubectl get pods -l app=user-service --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""))

if [ ${#USER_PODS[@]} -eq 0 ]; then
    echo "✗ ERROR: No user-service pods found!"
    kubectl get pods -l app=user-service
    exit 1
fi

echo "Found ${#USER_PODS[@]} user-service pod(s):"
for pod in "${USER_PODS[@]}"; do
    echo "  - $pod"
done
echo ""

# Check each pod
for pod in "${USER_PODS[@]}"; do
    echo "=== Pod: $pod ==="
    
    # Status
    READY=$(kubectl get pod "$pod" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    RESTARTS=$(kubectl get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    AGE=$(kubectl get pod "$pod" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "unknown")
    
    echo "  Status: Ready=$READY, Restarts=$RESTARTS, Age=$AGE"
    
    # Recent events
    echo ""
    echo "  Recent events:"
    kubectl get events --field-selector involvedObject.name=$pod --sort-by='.lastTimestamp' 2>/dev/null | tail -5 || echo "    (no recent events)"
    
    # Logs
    echo ""
    echo "  Recent logs (last 20 lines):"
    LOGS=$(kubectl logs "$pod" --tail=20 2>&1)
    if [ -n "$LOGS" ]; then
        echo "$LOGS" | head -20
    else
        echo "    (no logs)"
    fi
    
    # Check for errors
    ERROR_COUNT=$(echo "$LOGS" | grep -ci "error\|fail\|exception\|crash" || echo "0")
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo ""
        echo "  ⚠ Found $ERROR_COUNT potential errors in logs"
        echo "  Error lines:"
        echo "$LOGS" | grep -i "error\|fail\|exception\|crash" | head -5
    fi
    
    echo ""
done

# Check service endpoints
echo "=== Service Endpoints ==="
kubectl get endpoints user-service

echo ""
echo "=== Making a Test Request ==="
echo ""
echo "Now make a request and watch the logs:"
echo ""
echo "In one terminal, watch user-service logs:"
echo "  kubectl logs -f ${USER_PODS[0]} --tail=0"
echo ""
echo "In another terminal, make a request:"
echo "  curl -X POST http://localhost:8080/wrk2-api/user/register \\"
echo "    -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "    -d 'user_id=99999&username=testuser&first_name=Test&last_name=User&password=test123'"
echo ""
echo "If you see connection attempts in user-service logs, connectivity works!"
echo "If you don't see anything, the connection isn't reaching user-service."

