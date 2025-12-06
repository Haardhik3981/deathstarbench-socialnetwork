#!/bin/bash

# Quick cluster health check - run this when API is accessible

set +e

echo "=== QUICK CLUSTER CHECK ==="
echo ""

# 1. API connectivity
echo "1. Testing API connectivity..."
if kubectl get nodes &>/dev/null; then
    echo "✓ API is reachable"
else
    echo "❌ API is NOT reachable - wait and retry"
    exit 1
fi

# 2. Check nginx
echo ""
echo "2. Checking nginx/ingress..."
kubectl get pods -n default | grep -E "nginx|ingress" || echo "No nginx/ingress pods found"

# 3. Check critical services
echo ""
echo "3. Critical service pods:"
for svc in compose-post-service user-service unique-id-service social-graph-service; do
    kubectl get pods -n default -l app="$svc" --no-headers 2>/dev/null | head -1 | awk '{printf "  %s: %s (restarts: %s)\n", $1, $3, $4}'
done

# 4. Check HPA
echo ""
echo "4. HPA status:"
kubectl get hpa -n default 2>/dev/null | grep -E "compose-post|user-service|social-graph" || echo "Cannot retrieve HPA"

# 5. Check node resources
echo ""
echo "5. Node resources:"
kubectl top nodes 2>/dev/null || echo "Cannot get node metrics"

echo ""
echo "=== Done ==="

