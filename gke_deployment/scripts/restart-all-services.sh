#!/bin/bash

# Script to restart all service deployments

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_info "Restarting all service deployments..."

# List of service deployments (with -deployment suffix)
SERVICES=(
    "compose-post-service-deployment"
    "home-timeline-service-deployment"
    "media-service-deployment"
    "post-storage-service-deployment"
    "social-graph-service-deployment"
    "text-service-deployment"
    "unique-id-service-deployment"
    "url-shorten-service-deployment"
    "user-mention-service-deployment"
    "user-service-deployment"
    "user-timeline-service-deployment"
)

for service in "${SERVICES[@]}"; do
    if kubectl get deployment "$service" &>/dev/null; then
        print_info "Restarting: $service"
        kubectl rollout restart deployment/"$service"
    else
        print_warn "Deployment not found: $service (skipping)"
    fi
done

print_info "Done! Deployments will restart with new ConfigMap."

