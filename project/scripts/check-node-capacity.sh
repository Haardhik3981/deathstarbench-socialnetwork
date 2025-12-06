#!/bin/bash

# Check Node CPU and Memory Capacity vs Allocated Resources

set +e

echo "=== NODE CAPACITY ANALYSIS ==="
echo ""

kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU-CAPACITY:.status.capacity.cpu,MEMORY-CAPACITY:.status.capacity.memory --no-headers | while read -r node_name cpu_cap mem_cap; do
    echo "Node: $node_name"
    echo "  Capacity: CPU=$cpu_cap, Memory=$mem_cap"
    
    # Get allocated resources
    ALLOCATED=$(kubectl describe node "$node_name" 2>/dev/null | grep -A 3 "Allocated resources:" | tail -2)
    echo "  Allocated:"
    echo "$ALLOCATED" | sed 's/^/    /'
    
    # Get actual usage
    USAGE=$(kubectl top node "$node_name" 2>/dev/null | tail -1)
    if [ -n "$USAGE" ]; then
        echo "  Usage: $USAGE"
    fi
    echo ""
done

echo "=== PENDING PODS ==="
PENDING=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "Total pending pods: $PENDING"

if [ "$PENDING" -gt 0 ]; then
    echo ""
    echo "Pending pod details:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Pending -o wide
    echo ""
    echo "To see why a pod is pending:"
    echo "  kubectl describe pod <pod-name> -n <namespace>"
fi

echo ""
echo "=== RECOMMENDATIONS ==="
echo ""
echo "If nodes are at capacity:"
echo "  1. Enable cluster autoscaling (GKE):"
echo "     gcloud container clusters update <cluster-name> --enable-autoscaling --min-nodes=3 --max-nodes=10"
echo ""
echo "  2. Reduce resource requests for non-critical pods"
echo ""
echo "  3. Delete pending pods that can't be scheduled:"
echo "     kubectl delete pod <pod-name> -n <namespace>"
echo ""

