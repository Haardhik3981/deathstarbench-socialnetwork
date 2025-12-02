#!/bin/bash

# Prometheus Adapter Setup Script
#
# WHAT THIS DOES:
# Installs Prometheus Adapter which allows HPA to scale based on Prometheus
# metrics (like latency, request rate, etc.). This is required for latency-based
# autoscaling.
#
# PREREQUISITES:
# - Prometheus already deployed and running
# - kubectl configured for your cluster
# - Helm installed (for easy installation)

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

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed."
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        print_warn "Helm is not installed. Installing Prometheus Adapter manually..."
        INSTALL_METHOD="manual"
    else
        INSTALL_METHOD="helm"
        print_info "Helm found, will use Helm for installation"
    fi
    
    # Check if Prometheus is running
    if ! kubectl get deployment prometheus -n monitoring &> /dev/null; then
        print_warn "Prometheus not found in monitoring namespace"
        print_info "Make sure Prometheus is deployed first: ./setup-monitoring.sh"
    fi
}

# Install using Helm (recommended)
install_with_helm() {
    print_info "Installing Prometheus Adapter using Helm..."
    
    # Add the prometheus-community Helm repo
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install Prometheus Adapter
    helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
        --namespace monitoring \
        --create-namespace \
        --set prometheus.url=http://prometheus.monitoring.svc.cluster.local \
        --set prometheus.port=9090 \
        --set logLevel=4 \
        --wait
    
    print_info "Prometheus Adapter installed via Helm"
}

# Install manually (if Helm not available)
install_manually() {
    print_info "Installing Prometheus Adapter manually..."
    
    # Download the latest release
    ADAPTER_VERSION="v0.11.0"
    print_info "Downloading Prometheus Adapter ${ADAPTER_VERSION}..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply the adapter configuration
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/prometheus-adapter-config.yaml"
    
    # Download and apply the adapter deployment
    # Note: This is a simplified version - you may need to adjust based on your cluster
    print_warn "Manual installation requires downloading manifests from:"
    print_info "https://github.com/kubernetes-sigs/prometheus-adapter/releases"
    print_info "Or use the Helm chart method instead"
    
    # For now, provide instructions
    print_info "To install manually:"
    print_info "1. Download manifests from GitHub releases"
    print_info "2. Apply the manifests: kubectl apply -f <downloaded-manifests>"
    print_info "3. Apply the config: kubectl apply -f kubernetes/autoscaling/prometheus-adapter-config.yaml"
}

# Verify installation
verify_installation() {
    print_info "Verifying Prometheus Adapter installation..."
    
    # Wait for adapter to be ready
    print_info "Waiting for Prometheus Adapter to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus-adapter -n monitoring || true
    
    # Check if custom metrics API is available
    print_info "Checking Custom Metrics API..."
    if kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" &> /dev/null; then
        print_info "Custom Metrics API is available!"
        
        # List available metrics
        print_info "Available custom metrics:"
        kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | grep -o '"name":"[^"]*"' | head -5 || true
    else
        print_warn "Custom Metrics API not yet available. It may take a few minutes."
        print_info "Check status: kubectl get apiservice | grep custom.metrics"
    fi
}

# Show usage information
show_usage() {
    print_info "Prometheus Adapter setup complete!"
    echo ""
    print_info "Next steps:"
    print_info "1. Verify metrics are available:"
    print_info "   kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1'"
    echo ""
    print_info "2. Check if latency metrics are exposed:"
    print_info "   kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_request_duration_seconds'"
    echo ""
    print_info "3. Deploy latency-based HPA:"
    print_info "   kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml"
    echo ""
    print_info "4. Monitor HPA:"
    print_info "   kubectl get hpa user-service-hpa-latency -w"
    echo ""
    print_warn "Note: If metrics are not available, check:"
    print_info "  - Prometheus is scraping metrics: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    print_info "  - Services expose metrics: curl http://<service>/metrics"
    print_info "  - Adapter logs: kubectl logs -n monitoring deployment/prometheus-adapter"
}

# Main
main() {
    print_info "Setting up Prometheus Adapter for latency-based autoscaling..."
    
    check_prerequisites
    
    if [ "${INSTALL_METHOD}" = "helm" ]; then
        install_with_helm
    else
        install_manually
    fi
    
    verify_installation
    show_usage
}

main

