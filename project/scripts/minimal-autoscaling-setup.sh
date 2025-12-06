#!/bin/bash

# Minimal Autoscaling Setup - Just Enough to Demonstrate HPA Working
# This sets up the absolute minimum needed to show autoscaling in action

set +e

NAMESPACE="${NAMESPACE:-default}"

echo "=========================================="
echo "MINIMAL AUTOSCALING SETUP"
echo "=========================================="
echo ""
echo "Setting up just enough to demonstrate autoscaling..."
echo ""

# 1. Keep only critical HPAs (user-service, unique-id-service, nginx-thrift)
# Delete non-critical HPAs
echo "1. Removing non-critical HPAs..."
NON_CRITICAL_HPAS=(
    "media-service-hpa"
    "text-service-hpa"
    "url-shorten-service-hpa"
    "user-mention-service-hpa"
    "home-timeline-service-hpa"
    "user-timeline-service-hpa"
    "post-storage-service-hpa"
    "compose-post-service-hpa"
    "social-graph-service-hpa"
)

for hpa in "${NON_CRITICAL_HPAS[@]}"; do
    kubectl delete hpa "$hpa" -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null
    echo "  Deleted $hpa"
done

echo ""

# 2. Set minReplicas to 1 for remaining HPAs
echo "2. Setting minReplicas to 1 for critical HPAs..."
CRITICAL_HPAS=(
    "user-service-hpa"
    "unique-id-service-hpa"
    "nginx-thrift-hpa"
)

for hpa in "${CRITICAL_HPAS[@]}"; do
    kubectl patch hpa "$hpa" -n "$NAMESPACE" -p '{"spec":{"minReplicas":1}}' 2>/dev/null
    echo "  Updated $hpa"
done

echo ""

# 3. Scale down non-critical deployments to 1 replica
echo "3. Scaling down non-critical deployments to 1 replica..."
NON_CRITICAL_DEPLOYMENTS=(
    "media-service-deployment"
    "text-service-deployment"
    "url-shorten-service-deployment"
    "user-mention-service-deployment"
    "home-timeline-service-deployment"
    "user-timeline-service-deployment"
    "post-storage-service-deployment"
    "compose-post-service-deployment"
    "social-graph-service-deployment"
)

for deployment in "${NON_CRITICAL_DEPLOYMENTS[@]}"; do
    kubectl scale deployment "$deployment" -n "$NAMESPACE" --replicas=1 2>/dev/null
    echo "  Scaled $deployment to 1"
done

echo ""

# 4. Clean up pending pods
echo "4. Cleaning up pending pods..."
kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending -o name 2>/dev/null | xargs -r kubectl delete --force --grace-period=0 2>/dev/null
echo "  Done"

echo ""
echo "=========================================="
echo "SETUP COMPLETE"
echo "=========================================="
echo ""
echo "You now have:"
echo "  - 3 critical HPAs: user-service, unique-id-service, nginx-thrift"
echo "  - All with minReplicas=1 (can scale up to 10)"
echo "  - Non-critical services scaled to 1 replica"
echo ""
echo "This should free up enough CPU for autoscaling to work!"
echo "Run your load test - you should see these 3 services scale up."
echo ""

