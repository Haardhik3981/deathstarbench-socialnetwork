#!/bin/bash

# Script to delete all pods so they restart with new deployment configurations
# This is useful when you've updated deployments (e.g., CPU requests, readiness probes)
# and want to force all pods to use the new configuration

set -e

# Colors
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

print_info "=== Restarting All Service Pods with New Configuration ==="
echo ""

# List of service deployments
SERVICES=(
    "compose-post-service-deployment"
    "home-timeline-service-deployment"
    "media-service-deployment"
    "nginx-thrift-deployment"
    "post-storage-service-deployment"
    "social-graph-service-deployment"
    "text-service-deployment"
    "unique-id-service-deployment"
    "url-shorten-service-deployment"
    "user-mention-service-deployment"
    "user-service-deployment"
    "user-timeline-service-deployment"
    "write-home-timeline-service-deployment"
)

print_info "This will delete all pods for the above services."
print_info "Kubernetes will automatically recreate them with the new configuration."
echo ""

# Ask for confirmation
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warn "Cancelled."
    exit 1
fi

echo ""
print_info "Deleting pods for each service..."
echo ""

FAILED=0
SUCCESS=0

for service in "${SERVICES[@]}"; do
    # Get deployment name without -deployment suffix for pod labels
    SERVICE_NAME=$(echo "$service" | sed 's/-deployment$//')
    
    # Check if deployment exists
    if ! kubectl get deployment "$service" -n default &>/dev/null; then
        print_warn "Deployment not found: $service (skipping)"
        continue
    fi
    
    print_info "Processing: $service"
    
    # Delete all pods for this service
    PODS=$(kubectl get pods -n default -l app="$SERVICE_NAME" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$PODS" ]; then
        print_warn "  No pods found for $service"
        continue
    fi
    
    # Delete each pod
    for pod in $PODS; do
        if kubectl delete pod "$pod" -n default &>/dev/null; then
            print_info "  ✓ Deleted pod: $pod"
            SUCCESS=$((SUCCESS + 1))
        else
            print_error "  ✗ Failed to delete pod: $pod"
            FAILED=$((FAILED + 1))
        fi
    done
    
    echo ""
done

echo ""
print_info "=== Summary ==="
print_info "Successfully deleted: $SUCCESS pods"
if [ $FAILED -gt 0 ]; then
    print_error "Failed to delete: $FAILED pods"
fi

echo ""
print_info "Pods are being recreated with new configurations..."
print_info "Monitor progress with: kubectl get pods -w"
echo ""
print_info "To check readiness probe status:"
print_info "  kubectl get pods -n default | grep -E '(0/1|CrashLoopBackOff)'"
echo ""

