#!/bin/bash

# Script to fix write-home-timeline-service deployment
# The binary may not exist in the image since it's commented out in CMakeLists.txt

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
echo "  Fixing write-home-timeline-service"
echo "=========================================="
echo ""

print_section "Issue Identified"
print_warn "WriteHomeTimelineService is commented out in CMakeLists.txt"
print_info "This means the binary may not be built into the Docker image"
echo ""

print_section "Options"
echo ""
print_info "Option 1: Try deployment without explicit command (use image's default)"
print_info "Option 2: Scale down the deployment (it's optional)"
echo ""

# Check current status
print_section "Current Status"
if kubectl get deployment write-home-timeline-service-deployment &> /dev/null; then
    READY=$(kubectl get deployment write-home-timeline-service-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment write-home-timeline-service-deployment -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    print_info "Current replicas: $READY/$DESIRED"
    
    if [ "$READY" -eq 0 ]; then
        print_warn "Service is not running"
    fi
else
    print_warn "Deployment not found"
fi

echo ""

# Apply the updated deployment (without command)
print_section "Applying Updated Deployment"
print_info "Removing explicit command to use image's default entrypoint..."
kubectl apply -f kubernetes/deployments/write-home-timeline-service-deployment.yaml
print_success "Deployment updated"

echo ""

# Wait and check
print_section "Waiting and Checking Status"
print_info "Waiting 30 seconds for pod to start..."
sleep 30

POD_NAME=$(kubectl get pods -l app=write-home-timeline-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POD_NAME" ]; then
    POD_STATUS=$(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    print_info "Pod status: $POD_STATUS"
    
    if [ "$POD_STATUS" = "Running" ]; then
        print_success "Pod is running!"
    else
        print_warn "Pod is not running (status: $POD_STATUS)"
        echo ""
        print_info "Checking logs..."
        kubectl logs "$POD_NAME" --tail=20 2>&1 | head -20 || print_warn "Could not retrieve logs"
        echo ""
        print_warn "If the pod is still failing, the binary likely doesn't exist in the image"
        print_info "You can scale it down since it's optional:"
        echo "  kubectl scale deployment write-home-timeline-service-deployment --replicas=0"
    fi
else
    print_warn "No pod found"
fi

echo ""
print_section "Summary"
print_info "write-home-timeline-service is OPTIONAL"
print_info "home-timeline-service can work without it (it updates Redis directly)"
print_info "This service only provides async processing via RabbitMQ"
echo ""

