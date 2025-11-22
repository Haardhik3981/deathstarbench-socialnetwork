#!/bin/bash

# Deployment Script for Nautilus Cluster
#
# WHAT THIS DOES:
# This script automates deployment to the Nautilus cluster. Nautilus is a research
# cluster, so some things work differently than GKE:
# - No managed LoadBalancer (use NodePort instead)
# - May need to set up Prometheus adapter manually
# - Resource quotas may apply
# - Different authentication method
#
# KEY DIFFERENCES FROM GKE:
# - NodePort services instead of LoadBalancer
# - Manual Prometheus setup may be required
# - VPA may need manual installation
# - Different image registry (Docker Hub or local registry)

set -e

# Configuration
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io/your-username}"  # Use Docker Hub or your registry

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed."
        exit 1
    fi
    
    # Check if kubectl is configured for Nautilus
    if ! kubectl cluster-info &> /dev/null; then
        print_error "kubectl is not configured or cannot connect to cluster."
        print_info "Make sure you've configured kubectl for Nautilus."
        exit 1
    fi
    
    print_info "Prerequisites check passed!"
}

# Convert LoadBalancer services to NodePort
convert_to_nodeport() {
    print_info "Converting services to NodePort for Nautilus..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Create temporary directory for modified manifests
    TEMP_DIR=$(mktemp -d)
    cp -r "${PROJECT_ROOT}/kubernetes" "${TEMP_DIR}/"
    
    # Modify nginx service to use NodePort
    sed -i.bak 's/type: LoadBalancer/type: NodePort/' "${TEMP_DIR}/kubernetes/services/nginx-service.yaml"
    
    # Modify Grafana service to use NodePort
    sed -i.bak 's/type: LoadBalancer/type: NodePort/' "${TEMP_DIR}/kubernetes/monitoring/grafana-deployment.yaml"
    
    # Add nodePort specification (optional - Kubernetes will assign one)
    # sed -i.bak '/port: 80/a\    nodePort: 30080' "${TEMP_DIR}/kubernetes/services/nginx-service.yaml"
    
    echo "${TEMP_DIR}"
}

# Create namespaces
create_namespaces() {
    print_info "Creating namespaces..."
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
}

# Deploy application
deploy_application() {
    print_info "Deploying application..."
    
    TEMP_DIR=$1
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Deploy ConfigMaps and Secrets
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/configmaps/"
    
    # Deploy services (using NodePort versions)
    kubectl apply -f "${TEMP_DIR}/kubernetes/services/"
    
    # Deploy deployments
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/"
    
    # Wait for deployments
    print_info "Waiting for deployments..."
    kubectl wait --for=condition=available --timeout=300s deployment/nginx-deployment || true
}

# Deploy monitoring
deploy_monitoring() {
    print_info "Deploying monitoring stack..."
    
    TEMP_DIR=$1
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Deploy Prometheus
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml"
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-deployment.yaml"
    
    # Deploy Grafana (using NodePort version)
    kubectl apply -f "${TEMP_DIR}/kubernetes/monitoring/grafana-deployment.yaml"
    
    print_warn "Note: You may need to set up Prometheus Adapter manually for HPA metrics."
    print_info "See: https://github.com/kubernetes-sigs/prometheus-adapter"
}

# Deploy autoscaling
deploy_autoscaling() {
    print_info "Deploying autoscaling..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Deploy HPA
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/"
    
    print_warn "HPA requires metrics-server or Prometheus Adapter."
    print_warn "Check if metrics-server is installed: kubectl get deployment metrics-server -n kube-system"
    
    # VPA may need manual installation
    print_warn "VPA may need to be installed separately on Nautilus."
    print_info "See: https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler"
}

# Show endpoints
show_endpoints() {
    print_info "Service endpoints:"
    
    # Get NodePort for Nginx
    NGINX_PORT=$(kubectl get service nginx-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    print_info "Nginx NodePort: ${NGINX_PORT}"
    print_info "  Access via: http://<node-ip>:${NGINX_PORT}"
    print_info "  Find node IP: kubectl get nodes -o wide"
    
    # Get NodePort for Grafana
    GRAFANA_PORT=$(kubectl get service grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    print_info "Grafana NodePort: ${GRAFANA_PORT}"
    print_info "  Access via: http://<node-ip>:${GRAFANA_PORT}"
    
    print_info "Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
}

# Cleanup temp files
cleanup() {
    if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
    fi
}

# Main
main() {
    print_info "Starting Nautilus deployment..."
    
    # Set trap to cleanup on exit
    trap cleanup EXIT
    
    check_prerequisites
    create_namespaces
    
    TEMP_DIR=$(convert_to_nodeport)
    
    deploy_application "${TEMP_DIR}"
    deploy_monitoring "${TEMP_DIR}"
    deploy_autoscaling
    
    print_info "Deployment complete!"
    echo ""
    show_endpoints
    echo ""
    print_info "To check status:"
    print_info "  kubectl get pods --all-namespaces"
    print_info "  kubectl get services --all-namespaces"
}

main

