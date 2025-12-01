#!/bin/bash

# Monitoring Setup Script
#
# WHAT THIS DOES:
# This script sets up Prometheus and Grafana for monitoring in Kubernetes.
# It can be run independently if you've already deployed the application and just want to
# add monitoring.
#
# KEY FEATURES:
# - Deploys Prometheus with Kubernetes service discovery
# - Deploys Grafana with Prometheus as data source
# - Configures persistent storage for metrics
# - Sets up RBAC permissions for Prometheus
#
# IMPORTANT:
# - This script is for KUBERNETES ONLY (GKE, Nautilus, etc.)
# - For local docker-compose, monitoring is not set up (use docker-compose metrics or skip)
# - Requires kubectl to be configured and pointing to your cluster

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# Check if kubectl is available and configured
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed."
        print_info "Install from: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null 2>&1; then
        print_error "kubectl is not configured or cannot connect to cluster."
        print_info "Make sure kubectl is configured:"
        print_info "  - For GKE: gcloud container clusters get-credentials <cluster-name> --zone <zone>"
        print_info "  - For Nautilus: Follow Nautilus cluster access instructions"
        exit 1
    fi
    
    print_info "kubectl is configured and connected to cluster"
}

# Create monitoring namespace
create_namespace() {
    print_info "Creating monitoring namespace..."
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
}

# Deploy Prometheus
deploy_prometheus() {
    print_info "Deploying Prometheus..."
    
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml"
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-deployment.yaml"
    
    print_info "Waiting for Prometheus to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring || true
}

# Deploy Grafana
deploy_grafana() {
    print_info "Deploying Grafana..."
    
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/grafana-deployment.yaml"
    
    print_info "Waiting for Grafana to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring || true
}

# Show access information
show_access() {
    print_info "Monitoring access information:"
    echo ""
    
    # Prometheus
    print_info "Prometheus:"
    print_info "  Port-forward: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    print_info "  Then access: http://localhost:9090"
    echo ""
    
    # Grafana
    GRAFANA_TYPE=$(kubectl get service grafana -n monitoring -o jsonpath='{.spec.type}' 2>/dev/null || echo "ClusterIP")
    
    if [ "${GRAFANA_TYPE}" = "LoadBalancer" ]; then
        GRAFANA_IP=$(kubectl get service grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
        print_info "Grafana: http://${GRAFANA_IP}:3000"
    elif [ "${GRAFANA_TYPE}" = "NodePort" ]; then
        GRAFANA_PORT=$(kubectl get service grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
        print_info "Grafana NodePort: ${GRAFANA_PORT}"
        print_info "  Access via: http://<node-ip>:${GRAFANA_PORT}"
    else
        print_info "Grafana:"
        print_info "  Port-forward: kubectl port-forward -n monitoring svc/grafana 3000:3000"
        print_info "  Then access: http://localhost:3000"
    fi
    
    print_info "  Default credentials: admin/admin"
    print_warn "  Change the default password after first login!"
    echo ""
    
    print_info "To verify Prometheus is scraping metrics:"
    print_info "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    print_info "  Then visit: http://localhost:9090/targets"
}

# Main
main() {
    print_info "Setting up monitoring stack for Kubernetes..."
    print_warn "Note: This script is for Kubernetes only (GKE/Nautilus)"
    print_warn "For local docker-compose, monitoring is not available"
    echo ""
    
    check_kubectl
    create_namespace
    deploy_prometheus
    deploy_grafana
    
    print_info "Monitoring setup complete!"
    echo ""
    show_access
    echo ""
    print_info "To access monitoring from local machine:"
    print_info "  Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    print_info "  Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
}

main

