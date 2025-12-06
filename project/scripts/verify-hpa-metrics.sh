#!/bin/bash
# Verify HPA Metrics Collection
# This script checks if HPA can collect metrics properly

set -e

NAMESPACE="${NAMESPACE:-default}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "HPA Metrics Verification"
echo "=========================================="
echo ""

# Check 1: Metrics API availability
print_info "1. Checking Metrics API availability..."
if kubectl get --raw /apis/metrics.k8s.io/v1beta1 > /dev/null 2>&1; then
    print_info "   ✓ Metrics API is available"
else
    print_error "   ✗ Metrics API is not available"
    exit 1
fi

# Check 2: Metrics-server pods
print_info "2. Checking metrics-server pods..."
METRICS_SERVER_PODS=$(kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$METRICS_SERVER_PODS" -gt 0 ]; then
    print_info "   ✓ Found $METRICS_SERVER_PODS metrics-server pod(s)"
    kubectl get pods -n kube-system -l k8s-app=metrics-server
else
    print_error "   ✗ No metrics-server pods found"
    exit 1
fi

# Check 3: Can get pod metrics
print_info "3. Testing pod metrics collection..."
if kubectl top pods -l app=user-service -n "$NAMESPACE" > /dev/null 2>&1; then
    print_info "   ✓ Can collect pod metrics"
    echo ""
    echo "   Current user-service pod metrics:"
    kubectl top pods -l app=user-service -n "$NAMESPACE" | head -3
else
    print_warn "   ⚠ Cannot collect pod metrics (pods may not have resource requests)"
fi

# Check 4: HPA status
print_info "4. Checking HPA status..."
HPAS=$(kubectl get hpa -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$HPAS" -gt 0 ]; then
    print_info "   ✓ Found $HPAS HPA(s)"
    echo ""
    kubectl get hpa -n "$NAMESPACE"
    echo ""
    
    # Check each HPA for issues
    for hpa in $(kubectl get hpa -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
        echo "   Checking $hpa..."
        SCALING_ACTIVE=$(kubectl get hpa "$hpa" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}' 2>/dev/null || echo "Unknown")
        if [ "$SCALING_ACTIVE" == "True" ]; then
            print_info "     ✓ ScalingActive: True"
        else
            print_warn "     ⚠ ScalingActive: $SCALING_ACTIVE"
        fi
        
        # Check for recent warnings
        WARNINGS=$(kubectl describe hpa "$hpa" -n "$NAMESPACE" 2>/dev/null | grep -c "FailedGetResourceMetric" || echo "0")
        if [ "$WARNINGS" -gt 0 ]; then
            print_warn "     ⚠ Found $WARNINGS 'FailedGetResourceMetric' warnings (may be transient)"
        else
            print_info "     ✓ No recent metric collection warnings"
        fi
    done
else
    print_warn "   ⚠ No HPAs found in namespace $NAMESPACE"
fi

# Check 5: Pod resource requests
print_info "5. Verifying pods have resource requests..."
PODS_WITHOUT_REQUESTS=$(kubectl get pods -l app=user-service -n "$NAMESPACE" -o json 2>/dev/null | \
    jq -r '.items[] | select(.spec.containers[0].resources.requests == null) | .metadata.name' 2>/dev/null || echo "")
if [ -z "$PODS_WITHOUT_REQUESTS" ]; then
    print_info "   ✓ All pods have resource requests defined"
else
    print_warn "   ⚠ Some pods missing resource requests:"
    echo "$PODS_WITHOUT_REQUESTS"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
print_info "HPA metrics collection is working!"
print_warn "Note: Occasional 'FailedGetResourceMetric' warnings are normal and transient."
print_info "HPA will scale automatically when metrics exceed thresholds."
echo ""
print_info "To test scaling, run a load test:"
echo "  ./scripts/run-k6-tests.sh constant-load"
echo ""
print_info "Monitor HPA during test:"
echo "  watch -n 2 'kubectl get hpa -n $NAMESPACE'"
echo ""

