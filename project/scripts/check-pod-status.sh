#!/bin/bash

# Check pod status and ensure we're connecting to the right one

set -e

echo "=== Checking nginx-thrift Pod Status ==="
echo ""

# Check all pods
echo "All nginx-thrift pods:"
kubectl get pods -l app=nginx-thrift -o wide

echo ""
echo "Pod details:"
kubectl get pods -l app=nginx-thrift -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.podIP}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}'

echo ""
echo "Checking for old pods that should be terminated:"
OLD_PODS=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$OLD_PODS" ]; then
    echo "⚠ Found non-running pods:"
    for pod in $OLD_PODS; do
        echo "  - $pod"
        kubectl get pod "$pod" -o jsonpath='  Status: {.status.phase}, Created: {.metadata.creationTimestamp}{"\n"}'
    done
    echo ""
    echo "These should be cleaned up automatically, but you can force delete them:"
    echo "  kubectl delete pod $OLD_PODS"
else
    echo "✓ No old pods found"
fi

echo ""
echo "Current running pod:"
RUNNING_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$RUNNING_POD" ]; then
    echo "✗ ERROR: No running pod found!"
    echo ""
    echo "Checking all pods:"
    kubectl get pods -l app=nginx-thrift
    echo ""
    echo "Checking pod events:"
    kubectl get pods -l app=nginx-thrift -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.containerStatuses[0].state}{"\n"}{end}'
else
    echo "✓ Running pod: $RUNNING_POD"
    echo ""
    echo "Pod status:"
    kubectl get pod "$RUNNING_POD" -o jsonpath='  Phase: {.status.phase}{"\n"}'
    kubectl get pod "$RUNNING_POD" -o jsonpath='  Ready: {.status.containerStatuses[0].ready}{"\n"}'
    kubectl get pod "$RUNNING_POD" -o jsonpath='  IP: {.status.podIP}{"\n"}'
    kubectl get pod "$RUNNING_POD" -o jsonpath='  Created: {.metadata.creationTimestamp}{"\n"}'
    
    echo ""
    echo "Checking if port-forward is needed:"
    echo "  If you're using port-forward, make sure it's pointing to: $RUNNING_POD"
    echo "  Restart port-forward: kubectl port-forward pod/$RUNNING_POD 8080:8080"
fi

echo ""
echo "Service endpoints:"
kubectl get endpoints nginx-thrift-service 2>/dev/null || echo "  (Service not found - check service name)"

echo ""
echo "=== Recommendations ==="
echo ""
echo "1. If old pods exist, delete them:"
echo "   kubectl delete pod <old-pod-name>"
echo ""
echo "2. Restart port-forward to ensure it's pointing to the new pod:"
echo "   kubectl port-forward svc/nginx-thrift-service 8080:8080"
echo "   OR"
echo "   kubectl port-forward pod/$RUNNING_POD 8080:8080"
echo ""
echo "3. Check pod logs for errors:"
if [ -n "$RUNNING_POD" ]; then
    echo "   kubectl logs $RUNNING_POD --tail=50"
fi
