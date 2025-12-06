#!/bin/bash

# Check Service Connections Script
# Diagnoses connection issues between microservices

set +e

NAMESPACE="${NAMESPACE:-default}"

echo "=== Service Connection Check ==="
echo ""

# Check if social-graph-service pods are running
echo "1. Social Graph Service Status:"
SOCIAL_GRAPH_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=social-graph-service --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "$SOCIAL_GRAPH_PODS" -eq 0 ]; then
    echo "❌ No social-graph-service pods found!"
    echo "   This is likely the problem - user-service can't connect to social-graph-service"
else
    echo "✓ Found $SOCIAL_GRAPH_PODS social-graph-service pod(s)"
    kubectl get pods -n "$NAMESPACE" -l app=social-graph-service
fi

# Check service endpoints
echo ""
echo "2. Service Endpoints:"
SOCIAL_GRAPH_ENDPOINTS=$(kubectl get endpoints social-graph-service -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)

if [ "$SOCIAL_GRAPH_ENDPOINTS" -eq 0 ]; then
    echo "❌ social-graph-service has NO endpoints!"
    echo "   This means pods aren't ready or service selector is wrong"
else
    echo "✓ social-graph-service has $SOCIAL_GRAPH_ENDPOINTS endpoint(s)"
fi

# Check all microservice deployments
echo ""
echo "3. All Microservice Deployments:"
MICROSERVICES=(
    "user-service"
    "social-graph-service"
    "user-timeline-service"
    "compose-post-service"
    "home-timeline-service"
    "post-storage-service"
    "media-service"
    "text-service"
    "unique-id-service"
    "url-shorten-service"
    "user-mention-service"
)

for service in "${MICROSERVICES[@]}"; do
    READY=$(kubectl get deployment "${service}-deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "${service}-deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
        echo "  ✓ $service: $READY/$DESIRED ready"
    else
        echo "  ❌ $service: $READY/$DESIRED ready"
    fi
done

# Check service DNS resolution
echo ""
echo "4. Service DNS Resolution Test:"
USER_POD=$(kubectl get pods -n "$NAMESPACE" -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$USER_POD" ]; then
    echo "Testing DNS from user-service pod: $USER_POD"
    
    # Test if social-graph-service is resolvable (try multiple methods)
    DNS_RESOLVES=false
    
    # Method 1: getent hosts (most reliable, available in most containers)
    if kubectl exec -n "$NAMESPACE" "$USER_POD" -- getent hosts social-graph-service 2>/dev/null | grep -q "social-graph-service"; then
        DNS_RESOLVES=true
    # Method 2: nslookup (if available)
    elif kubectl exec -n "$NAMESPACE" "$USER_POD" -- nslookup social-graph-service 2>/dev/null | grep -q "Name:"; then
        DNS_RESOLVES=true
    # Method 3: ping -c 1 (if available, just to check DNS)
    elif kubectl exec -n "$NAMESPACE" "$USER_POD" -- ping -c 1 -W 1 social-graph-service 2>/dev/null | grep -q "PING"; then
        DNS_RESOLVES=true
    fi
    
    if [ "$DNS_RESOLVES" = true ]; then
        echo "  ✓ social-graph-service DNS resolves"
    else
        echo "  ⚠ social-graph-service DNS test inconclusive (but port connectivity test below is more reliable)"
    fi
    
    # Test port connectivity
    if kubectl exec -n "$NAMESPACE" "$USER_POD" -- timeout 2 bash -c "echo > /dev/tcp/social-graph-service/9090" 2>/dev/null; then
        echo "  ✓ Port 9090 on social-graph-service is reachable"
    else
        echo "  ❌ Port 9090 on social-graph-service is NOT reachable"
    fi
else
    echo "  ⚠ Cannot test (no user-service pods found)"
fi

echo ""
echo "=== Recommendations ==="
echo ""
echo "If social-graph-service has no pods or endpoints:"
echo "  1. Check deployment: kubectl get deployment social-graph-service-deployment -n $NAMESPACE"
echo "  2. Check pod status: kubectl get pods -n $NAMESPACE -l app=social-graph-service"
echo "  3. Check pod logs: kubectl logs -n $NAMESPACE -l app=social-graph-service --tail=50"
echo "  4. Check events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | grep social-graph"
echo ""

