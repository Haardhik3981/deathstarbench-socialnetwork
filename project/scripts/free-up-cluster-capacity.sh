#!/bin/bash

# Free Up Cluster Capacity - Reduce Resource Requests to Allow Autoscaling
# This script reduces CPU requests for non-critical services to free up capacity
# so HPAs can actually scale during your load tests

set +e

NAMESPACE="${NAMESPACE:-default}"

echo "=========================================="
echo "FREEING UP CLUSTER CAPACITY"
echo "=========================================="
echo ""
echo "This will reduce CPU requests for non-critical services"
echo "to allow autoscaling to work with your 3-node cluster."
echo ""

# Services to reduce (non-critical or can handle lower resources)
REDUCE_SERVICES=(
    "media-service"
    "text-service"
    "url-shorten-service"
    "user-mention-service"
    "home-timeline-service"
    "user-timeline-service"
    "post-storage-service"
)

# Reduce CPU requests to 50m (from typical 100-200m)
NEW_CPU_REQUEST="50m"

echo "Reducing CPU requests for non-critical services..."
echo ""

for service in "${REDUCE_SERVICES[@]}"; do
    DEPLOYMENT="${service}-deployment"
    echo "Processing $DEPLOYMENT..."
    
    # Get current CPU request
    CURRENT_CPU=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
    
    if [ -n "$CURRENT_CPU" ] && [ "$CURRENT_CPU" != "null" ]; then
        echo "  Current CPU request: $CURRENT_CPU"
        echo "  Setting to: $NEW_CPU_REQUEST"
        
        # Patch the deployment
        kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"${service}\",\"resources\":{\"requests\":{\"cpu\":\"${NEW_CPU_REQUEST}\"}}}]}}}}" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "  ✓ Updated"
        else
            echo "  ⚠ Failed to update"
        fi
    else
        echo "  ⚠ No CPU request found (may not have resource requests set)"
    fi
    echo ""
done

echo "=========================================="
echo "REDUCING MIN REPLICAS FOR NON-CRITICAL HPAs"
echo "=========================================="
echo ""

# Reduce minReplicas to 1 for non-critical services (frees up 1 pod per service)
REDUCE_HPA_MIN=(
    "media-service-hpa"
    "text-service-hpa"
    "url-shorten-service-hpa"
    "user-mention-service-hpa"
    "home-timeline-service-hpa"
    "user-timeline-service-hpa"
    "post-storage-service-hpa"
)

for hpa in "${REDUCE_HPA_MIN[@]}"; do
    echo "Reducing minReplicas for $hpa to 1..."
    kubectl patch hpa "$hpa" -n "$NAMESPACE" -p '{"spec":{"minReplicas":1}}' 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "  ✓ Updated"
    else
        echo "  ⚠ Failed"
    fi
done

echo ""
echo "=========================================="
echo "CLEANING UP PENDING PODS"
echo "=========================================="
echo ""

# Delete pending pods
PENDING_PODS=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending --no-headers 2>/dev/null | awk '{print $1}')

if [ -n "$PENDING_PODS" ]; then
    echo "$PENDING_PODS" | while read -r pod; do
        if [ -n "$pod" ]; then
            echo "Deleting pending pod: $pod"
            kubectl delete pod "$pod" -n "$NAMESPACE" --force --grace-period=0 2>/dev/null
        fi
    done
else
    echo "No pending pods found"
fi

echo ""
echo "=========================================="
echo "WAITING FOR CHANGES TO PROPAGATE"
echo "=========================================="
echo "Waiting 30 seconds for pods to adjust..."
sleep 30

echo ""
echo "=========================================="
echo "CURRENT CLUSTER STATUS"
echo "=========================================="
echo ""

# Show node capacity
echo "Node CPU allocation:"
kubectl describe nodes | grep -A 3 "Allocated resources:" | grep "cpu" | head -3

echo ""
echo "Pending pods:"
PENDING_COUNT=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "  Count: $PENDING_COUNT"

echo ""
echo "=========================================="
echo "DONE!"
echo "=========================================="
echo ""
echo "You should now have enough capacity for autoscaling."
echo "Try running your load test again - HPAs should be able to scale now."
echo ""

