#!/bin/bash

# Quick diagnosis script - run this first to identify the issue

set +e

NAMESPACE="${NAMESPACE:-default}"

echo "=== Quick Diagnosis ==="
echo ""

# Check for multiple HPAs (conflict)
echo "1. Checking for HPA conflicts..."
HPAS=$(kubectl get hpa -n "$NAMESPACE" -o name 2>/dev/null | grep user-service)
HPA_COUNT=$(echo "$HPAS" | wc -l | tr -d ' ')

if [ "$HPA_COUNT" -gt 1 ]; then
    echo "⚠️  WARNING: Multiple HPAs found for user-service!"
    echo "$HPAS"
    echo ""
    echo "This can cause conflicts. You should only have ONE HPA active."
    echo "Delete the others: kubectl delete hpa <name> -n $NAMESPACE"
    echo ""
fi

# Check HPA status
echo "2. HPA Status:"
for hpa in $HPAS; do
    HPA_NAME=$(echo "$hpa" | sed 's/.*\///')
    echo "--- $HPA_NAME ---"
    kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" 2>/dev/null | tail -1
    echo ""
    
    # Check if metrics are available
    METRICS=$(kubectl describe hpa "$HPA_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 5 "Metrics:")
    if echo "$METRICS" | grep -q "unknown"; then
        echo "⚠️  HPA has unknown metrics - this could be the problem!"
    fi
    if echo "$METRICS" | grep -q "unable to get"; then
        echo "⚠️  HPA cannot get metrics - Prometheus Adapter may not be working!"
    fi
done

# Check pod status
echo ""
echo "3. Pod Status:"
kubectl get pods -n "$NAMESPACE" -l app=user-service 2>/dev/null

# Check for recent restarts
echo ""
echo "4. Pod Restarts (last hour):"
kubectl get pods -n "$NAMESPACE" -l app=user-service --no-headers 2>/dev/null | while read -r line; do
    POD_NAME=$(echo "$line" | awk '{print $1}')
    RESTARTS=$(echo "$line" | awk '{print $4}')
    if [ "$RESTARTS" -gt 0 ]; then
        echo "⚠️  $POD_NAME: $RESTARTS restart(s)"
    fi
done

# Check service endpoints
echo ""
echo "5. Service Endpoints:"
ENDPOINTS=$(kubectl get endpoints nginx-thrift-service -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
if [ "$ENDPOINTS" -eq 0 ]; then
    echo "❌ nginx-thrift-service has NO endpoints - this is likely the problem!"
else
    echo "✓ nginx-thrift-service has $ENDPOINTS endpoint(s)"
fi

# Quick log check
echo ""
echo "6. Recent Errors in Pod Logs:"
FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$FIRST_POD" ]; then
    echo "Checking $FIRST_POD (last 5 lines):"
    kubectl logs "$FIRST_POD" -n "$NAMESPACE" --tail=5 2>&1 | tail -5
else
    echo "No pods found"
fi

echo ""
echo "=== Next Steps ==="
echo "Run full diagnostic: ./scripts/diagnose-failures.sh"
echo ""


