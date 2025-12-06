#!/bin/bash

# Diagnostic Script for k6 Test Failures
# Helps identify why tests are failing (500 errors, high latency, etc.)

set +e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "  $1"
}

NAMESPACE="${NAMESPACE:-default}"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  k6 Test Failure Diagnostic"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Investigating: 100% failure rate, 500 errors, high latency"
echo ""

# 1. Check pod status
print_section "1. Pod Status"

echo "User Service Pods:"
kubectl get pods -n "$NAMESPACE" -l app=user-service --no-headers 2>/dev/null | while read -r line; do
    POD_NAME=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{print $3}')
    READY=$(echo "$line" | awk '{print $2}')
    RESTARTS=$(echo "$line" | awk '{print $4}')
    
    if [ "$STATUS" = "Running" ] && [[ "$READY" == *"/1" ]]; then
        print_success "$POD_NAME: $STATUS, Ready: $READY, Restarts: $RESTARTS"
    else
        print_error "$POD_NAME: $STATUS, Ready: $READY, Restarts: $RESTARTS"
    fi
done

echo ""
echo "Nginx-Thrift Pods:"
kubectl get pods -n "$NAMESPACE" -l app=nginx-thrift --no-headers 2>/dev/null | while read -r line; do
    POD_NAME=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{print $3}')
    READY=$(echo "$line" | awk '{print $2}')
    
    if [ "$STATUS" = "Running" ] && [[ "$READY" == *"/1" ]]; then
        print_success "$POD_NAME: $STATUS, Ready: $READY"
    else
        print_error "$POD_NAME: $STATUS, Ready: $READY"
    fi
done

# 2. Check HPA status
print_section "2. HPA Status"

HPA_NAME=$(kubectl get hpa -n "$NAMESPACE" -o name 2>/dev/null | grep user-service | head -1 | sed 's/.*\///')

if [ -n "$HPA_NAME" ]; then
    echo "Current HPA: $HPA_NAME"
    echo ""
    kubectl describe hpa "$HPA_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 20 "Metrics:"
    echo ""
    
    # Check if HPA is scaling
    DESIRED=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" -o jsonpath='{.status.desiredReplicas}' 2>/dev/null)
    CURRENT=$(kubectl get hpa "$HPA_NAME" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}' 2>/dev/null)
    
    if [ -n "$DESIRED" ] && [ -n "$CURRENT" ]; then
        if [ "$DESIRED" -gt "$CURRENT" ]; then
            print_warn "HPA wants $DESIRED replicas but only $CURRENT are running (scaling up?)"
        elif [ "$DESIRED" -lt "$CURRENT" ]; then
            print_warn "HPA wants $DESIRED replicas but $CURRENT are running (scaling down?)"
        else
            print_info "HPA desired ($DESIRED) matches current ($CURRENT)"
        fi
    fi
else
    print_warn "No HPA found for user-service"
fi

# 3. Check pod logs for errors
print_section "3. Recent Pod Logs (Errors)"

USER_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=user-service -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -n "$USER_PODS" ]; then
    for pod in $USER_PODS; do
        echo "--- $pod (last 20 lines) ---"
        kubectl logs "$pod" -n "$NAMESPACE" --tail=20 2>&1 | grep -i -E "error|exception|fatal|panic|500" || echo "  (no errors in last 20 lines)"
        echo ""
    done
else
    print_error "No user-service pods found"
fi

# 4. Check resource usage
print_section "4. Resource Usage"

if kubectl top pods -n "$NAMESPACE" -l app=user-service --no-headers 2>/dev/null | head -1 > /dev/null 2>&1; then
    echo "CPU and Memory Usage:"
    kubectl top pods -n "$NAMESPACE" -l app=user-service 2>/dev/null
    echo ""
    
    # Check for high CPU/memory
    kubectl top pods -n "$NAMESPACE" -l app=user-service --no-headers 2>/dev/null | while read -r line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        CPU=$(echo "$line" | awk '{print $2}')
        MEMORY=$(echo "$line" | awk '{print $3}')
        
        CPU_M=$(echo "$CPU" | sed 's/m//' | sed 's/^$/0/')
        if [ -n "$CPU_M" ] && [ "$CPU_M" -gt 800 ] 2>/dev/null; then
            print_warn "$POD_NAME: High CPU usage ($CPU)"
        fi
        
        MEM_M=$(echo "$MEMORY" | sed 's/Mi//')
        if [ -n "$MEM_M" ] && [ "$MEM_M" -gt 400 ] 2>/dev/null; then
            print_warn "$POD_NAME: High memory usage ($MEMORY)"
        fi
    done
else
    print_warn "Metrics server not available (cannot check resource usage)"
fi

# 5. Check service endpoints
print_section "5. Service Endpoints"

echo "Nginx-Thrift Service:"
ENDPOINTS=$(kubectl get endpoints nginx-thrift-service -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
if [ "$ENDPOINTS" -gt 0 ]; then
    print_success "nginx-thrift-service has $ENDPOINTS endpoint(s)"
    kubectl get endpoints nginx-thrift-service -n "$NAMESPACE" -o wide 2>/dev/null
else
    print_error "nginx-thrift-service has no endpoints!"
fi

echo ""
echo "User Service:"
USER_ENDPOINTS=$(kubectl get endpoints user-service -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
if [ "$USER_ENDPOINTS" -gt 0 ]; then
    print_success "user-service has $USER_ENDPOINTS endpoint(s)"
else
    print_error "user-service has no endpoints!"
fi

# 6. Check for OOM kills
print_section "6. OOM Kills and Restarts"

kubectl get pods -n "$NAMESPACE" -l app=user-service --no-headers 2>/dev/null | while read -r line; do
    POD_NAME=$(echo "$line" | awk '{print $1}')
    RESTARTS=$(echo "$line" | awk '{print $4}')
    
    if [ "$RESTARTS" -gt 0 ]; then
        print_warn "$POD_NAME: $RESTARTS restart(s)"
        echo "  Recent events:"
        kubectl describe pod "$POD_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 5 "Events:" | tail -5
    fi
done

# 7. Check VPA status (if enabled)
print_section "7. VPA Status (if enabled)"

VPA_NAME=$(kubectl get vpa -n "$NAMESPACE" -o name 2>/dev/null | grep user-service | head -1 | sed 's/.*\///')

if [ -n "$VPA_NAME" ]; then
    echo "VPA: $VPA_NAME"
    kubectl describe vpa "$VPA_NAME" -n "$NAMESPACE" 2>/dev/null | grep -A 10 "Recommendation:" || echo "  (no recommendations yet)"
else
    print_info "No VPA found for user-service"
fi

# 8. Test endpoint directly
print_section "8. Endpoint Connectivity Test"

NGINX_POD=$(kubectl get pods -n "$NAMESPACE" -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$NGINX_POD" ]; then
    print_info "Testing nginx-thrift endpoint from inside cluster..."
    
    # Try to curl the endpoint
    HTTP_CODE=$(kubectl exec -n "$NAMESPACE" "$NGINX_POD" -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "302" ]; then
        print_success "nginx-thrift responds (HTTP $HTTP_CODE)"
    else
        print_error "nginx-thrift not responding (HTTP $HTTP_CODE)"
    fi
else
    print_warn "Cannot test endpoint (nginx-thrift pod not found)"
fi

# 9. Check for recent changes
print_section "9. Recent Deployment Changes"

echo "User Service Deployment:"
kubectl get deployment user-service-deployment -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null
echo ""
echo "Recent events:"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | grep -i "user-service" | tail -10

# 10. Summary and recommendations
print_section "10. Summary & Recommendations"

echo "Based on the diagnostic:"
echo ""
print_info "1. Check if HPA is causing rapid scaling (check HPA status above)"
print_info "2. Check pod logs for specific error messages (see section 3)"
print_info "3. Verify service endpoints are healthy (see section 5)"
print_info "4. Check if resources are constrained (see section 4)"
echo ""
print_info "Common causes of 500 errors:"
echo "  - Pods are restarting (OOM kills, crashes)"
echo "  - Service has no endpoints (pods not ready)"
echo "  - Resource constraints (CPU throttling, memory pressure)"
echo "  - Application errors (check logs)"
echo "  - HPA scaling too aggressively (pods not ready when scaled)"
echo ""
print_info "Next steps:"
echo "  1. Review pod logs: kubectl logs <pod-name> -n $NAMESPACE"
echo "  2. Check HPA: kubectl describe hpa <hpa-name> -n $NAMESPACE"
echo "  3. Check events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
echo "  4. Test endpoint: curl http://<nginx-service-ip>:8080/"
echo ""

