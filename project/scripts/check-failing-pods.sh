#!/bin/bash

# Script to check and clean up failing pods
# Identifies old duplicate pods and helps clean them up

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
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
    echo "  $1"
}

echo ""
echo "=========================================="
echo "  Checking Failing Pods"
echo "=========================================="
echo ""

# Find pods in error states
print_section "Step 1: Finding Pods in Error States"

FAILING_PODS=$(kubectl get pods --no-headers 2>/dev/null | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull)" | awk '{print $1}' || true)

if [ -z "$FAILING_PODS" ]; then
    print_success "No failing pods found!"
    exit 0
fi

echo "Found failing pods:"
echo "$FAILING_PODS" | while read pod; do
    if [ -n "$pod" ]; then
        print_warn "  - $pod"
    fi
done

echo ""

# Check each failing pod
print_section "Step 2: Analyzing Failing Pods"

for pod in $FAILING_PODS; do
    if [ -z "$pod" ]; then
        continue
    fi
    
    echo ""
    print_info "Pod: $pod"
    
    # Get pod details
    POD_STATUS=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    POD_RESTARTS=$(kubectl get pod "$pod" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    POD_AGE=$(kubectl get pod "$pod" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "Unknown")
    
    print_info "  Status: $POD_STATUS"
    print_info "  Restarts: $POD_RESTARTS"
    print_info "  Created: $POD_AGE"
    
    # Get deployment name
    DEPLOYMENT=$(kubectl get pod "$pod" -o jsonpath='{.metadata.labels.app}' 2>/dev/null || echo "unknown")
    print_info "  App: $DEPLOYMENT"
    
    # Check if there are multiple pods for this deployment
    if [ "$DEPLOYMENT" != "unknown" ]; then
        ALL_PODS=$(kubectl get pods -l app="$DEPLOYMENT" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        RUNNING_PODS=$(kubectl get pods -l app="$DEPLOYMENT" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        print_info "  Total pods for this app: $ALL_PODS (Running: $RUNNING_PODS)"
        
        if [ "$ALL_PODS" -gt 1 ] && [ "$RUNNING_PODS" -ge 1 ]; then
            print_warn "  This appears to be a duplicate pod (other pods are running)"
        fi
    fi
    
    # Show recent logs
    print_info "  Recent logs (last 5 lines):"
    kubectl logs "$pod" --tail=5 2>&1 | sed 's/^/    /' || print_info "    (Could not retrieve logs)"
done

echo ""
print_section "Step 3: Recommendations"

echo ""
print_info "For each failing pod, you can:"
echo ""
print_info "1. Check full logs:"
echo "   kubectl logs <pod-name>"
echo ""
print_info "2. Check pod events:"
echo "   kubectl describe pod <pod-name>"
echo ""
print_info "3. If it's a duplicate (other pods are running), delete it:"
echo "   kubectl delete pod <pod-name>"
echo ""
print_info "4. If the deployment is wrong, restart it:"
echo "   kubectl rollout restart deployment/<deployment-name>"
echo ""

# Check for write-home-timeline-service specifically
if echo "$FAILING_PODS" | grep -q "write-home-timeline-service"; then
    echo ""
    print_warn "Note: write-home-timeline-service is optional"
    print_info "If it keeps failing, you can scale it down:"
    echo "   kubectl scale deployment write-home-timeline-service-deployment --replicas=0"
    echo ""
    print_info "Or delete the deployment entirely (it's optional):"
    echo "   kubectl delete deployment write-home-timeline-service-deployment"
    echo ""
fi

