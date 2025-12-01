#!/bin/bash

# Get Endpoint Script
#
# WHAT THIS DOES:
# Helper script to get the endpoint URL for the application.
# Works for both GKE (LoadBalancer) and local (docker-compose).
#
# USAGE:
#   ./get-endpoint.sh          # Auto-detect
#   ./get-endpoint.sh gke      # Force GKE
#   ./get-endpoint.sh local    # Force local

set -e

ENVIRONMENT="${1:-auto}"

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

# Auto-detect environment
if [ "${ENVIRONMENT}" = "auto" ]; then
    if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null 2>&1; then
        ENVIRONMENT="gke"
        print_info "Detected Kubernetes cluster"
    else
        ENVIRONMENT="local"
        print_info "No Kubernetes cluster detected, assuming local"
    fi
fi

if [ "${ENVIRONMENT}" = "gke" ]; then
    print_info "Getting GKE LoadBalancer endpoint..."
    
    # Try nginx-thrift-service first
    NGINX_IP=$(kubectl get service nginx-thrift-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    
    if [ -z "${NGINX_IP}" ] || [ "${NGINX_IP}" = "null" ]; then
        # Try legacy nginx-service
        NGINX_IP=$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    fi
    
    if [ -n "${NGINX_IP}" ] && [ "${NGINX_IP}" != "null" ]; then
        ENDPOINT="http://${NGINX_IP}:8080"
        print_info "Endpoint: ${ENDPOINT}"
        echo "${ENDPOINT}"
    else
        print_warn "LoadBalancer IP not found. Service may still be provisioning."
        print_info "Check status: kubectl get service nginx-thrift-service"
        print_info "Or use port-forward: kubectl port-forward svc/nginx-thrift-service 8080:8080"
        exit 1
    fi
else
    # Local environment
    ENDPOINT="http://localhost:8080"
    print_info "Local endpoint: ${ENDPOINT}"
    print_info "Make sure docker-compose is running: cd ../socialNetwork && docker-compose up"
    echo "${ENDPOINT}"
fi

