#!/bin/bash

# Comprehensive Cluster Overload Diagnostic Script
# Use this when experiencing connection failures during load tests

set +e

NAMESPACE="${NAMESPACE:-default}"

echo "=========================================="
echo "CLUSTER OVERLOAD DIAGNOSTIC"
echo "=========================================="
echo ""

# 1. Check Kubernetes API connectivity
echo "1. KUBERNETES API STATUS:"
if kubectl cluster-info &>/dev/null; then
    echo "  ✓ API server is reachable"
else
    echo "  ❌ API server is UNREACHABLE - cluster may be overwhelmed"
    echo "     This explains why 'kubectl get hpa' is failing"
    exit 1
fi
echo ""

# 2. Check node resources
echo "2. NODE RESOURCES:"
kubectl top nodes 2>/dev/null || echo "  ⚠ Cannot get node metrics (metrics-server may be down)"
echo ""

# 3. Check nginx/ingress status
echo "3. NGINX/INGRESS STATUS:"
NGINX_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=nginx --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$NGINX_PODS" -eq 0 ]; then
    # Try common ingress labels
    NGINX_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | wc -l | tr -d ' ')
fi

if [ "$NGINX_PODS" -gt 0 ]; then
    echo "  Found $NGINX_PODS nginx/ingress pod(s):"
    kubectl get pods -n "$NAMESPACE" -l app=nginx 2>/dev/null || kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=ingress-nginx 2>/dev/null
    echo ""
    echo "  Nginx pod resource usage:"
    kubectl top pods -n "$NAMESPACE" -l app=nginx 2>/dev/null || kubectl top pods -n "$NAMESPACE" -l app.kubernetes.io/name=ingress-nginx 2>/dev/null || echo "    ⚠ Cannot get metrics"
else
    echo "  ⚠ No nginx/ingress pods found - check your ingress configuration"
fi
echo ""

# 4. Check critical service pods (status and restarts)
echo "4. CRITICAL SERVICE POD STATUS:"
CRITICAL_SERVICES=("compose-post-service" "user-service" "unique-id-service" "social-graph-service")

for service in "${CRITICAL_SERVICES[@]}"; do
    echo "  $service:"
    PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null)
    if [ -z "$PODS" ]; then
        echo "    ❌ No pods found!"
    else
        echo "$PODS" | while read -r line; do
            POD_NAME=$(echo "$line" | awk '{print $1}')
            STATUS=$(echo "$line" | awk '{print $3}')
            RESTARTS=$(echo "$line" | awk '{print $4}')
            READY=$(echo "$line" | awk '{print $2}')
            
            if [ "$STATUS" != "Running" ] || [ "$READY" != "1/1" ]; then
                echo "    ❌ $POD_NAME: $STATUS (Ready: $READY, Restarts: $RESTARTS)"
            elif [ "$RESTARTS" != "0" ]; then
                echo "    ⚠ $POD_NAME: Running but has $RESTARTS restart(s)"
            else
                echo "    ✓ $POD_NAME: $STATUS (Restarts: $RESTARTS)"
            fi
        done
    fi
done
echo ""

# 5. Check HPA status and events
echo "5. HPA STATUS:"
HPAS=$(kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}')
if [ -z "$HPAS" ]; then
    echo "  ⚠ Cannot retrieve HPAs (API may be slow)"
else
    for hpa in $HPAS; do
        echo "  $hpa:"
        HPA_STATUS=$(kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}/{.spec.minReplicas}-{.spec.maxReplicas}' 2>/dev/null)
        CPU_TARGET=$(kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}%' 2>/dev/null || echo "N/A")
        echo "    Replicas: $HPA_STATUS | CPU: $CPU_TARGET"
        
        # Check for scaling events
        LAST_EVENT=$(kubectl describe hpa "$hpa" -n "$NAMESPACE" 2>/dev/null | grep -A 5 "Events:" | tail -3 | grep -i "scaled" || echo "")
        if [ -n "$LAST_EVENT" ]; then
            echo "    Recent: $LAST_EVENT"
        fi
    done
fi
echo ""

# 6. Check pod resource usage for critical services
echo "6. POD RESOURCE USAGE (Top 10 by CPU):"
kubectl top pods -n "$NAMESPACE" --sort-by=cpu 2>/dev/null | head -11 || echo "  ⚠ Cannot get pod metrics"
echo ""

# 7. Check for OOMKilled or CrashLoopBackOff pods
echo "7. POD FAILURES:"
FAILED_PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -E "Error|CrashLoopBackOff|OOMKilled|Pending" || echo "")
if [ -z "$FAILED_PODS" ]; then
    echo "  ✓ No failed pods detected"
else
    echo "  ❌ Failed pods found:"
    echo "$FAILED_PODS"
fi
echo ""

# 8. Check service endpoints
echo "8. SERVICE ENDPOINTS (Critical Services):"
for service in "${CRITICAL_SERVICES[@]}"; do
    ENDPOINTS=$(kubectl get endpoints "${service}-service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
    if [ "$ENDPOINTS" -eq 0 ]; then
        echo "  ❌ ${service}-service: NO endpoints (pods not ready)"
    else
        echo "  ✓ ${service}-service: $ENDPOINTS endpoint(s)"
    fi
done
echo ""

# 9. Check recent events
echo "9. RECENT CLUSTER EVENTS (Last 10):"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "  ⚠ Cannot retrieve events"
echo ""

# 10. Recommendations
echo "=========================================="
echo "RECOMMENDATIONS:"
echo "=========================================="
echo ""
echo "If API server is unreachable:"
echo "  - Cluster control plane may be resource-constrained"
echo "  - Wait for API to recover, then check node resources"
echo ""
echo "If nginx/ingress is the bottleneck:"
echo "  - Check: kubectl get pods -n $NAMESPACE -l app=nginx"
echo "  - Consider scaling nginx or increasing its resources"
echo ""
echo "If services are crashing:"
echo "  - Check logs: kubectl logs -n $NAMESPACE <pod-name>"
echo "  - Check resource limits: kubectl describe pod <pod-name> -n $NAMESPACE"
echo ""
echo "If HPA isn't scaling:"
echo "  - Check HPA events: kubectl describe hpa <hpa-name> -n $NAMESPACE"
echo "  - Verify metrics-server: kubectl get deployment metrics-server -n kube-system"
echo "  - Check if pods have resource requests: kubectl describe deployment <deployment> -n $NAMESPACE"
echo ""

