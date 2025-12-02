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

set -e  # Exit on error, but we handle timeouts gracefully

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

# Clean up existing monitoring resources (to prevent duplicates and permission issues)
cleanup_existing_monitoring() {
    print_info "Cleaning up any existing monitoring deployments..."
    
    # Scale down existing deployments if they exist
    if kubectl get deployment prometheus -n monitoring &>/dev/null; then
        print_info "Scaling down existing Prometheus deployment..."
        kubectl scale deployment prometheus -n monitoring --replicas=0 2>/dev/null || true
    fi
    
    if kubectl get deployment grafana -n monitoring &>/dev/null; then
        print_info "Scaling down existing Grafana deployment..."
        kubectl scale deployment grafana -n monitoring --replicas=0 2>/dev/null || true
    fi
    
    sleep 5
    
    # Delete old ReplicaSets to prevent duplicates
    OLD_RS=$(kubectl get rs -n monitoring --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [ -n "$OLD_RS" ]; then
        print_info "Cleaning up old ReplicaSets..."
        echo "$OLD_RS" | while read rs; do
            if [ -n "$rs" ] && [ "$rs" != "NAME" ]; then
                kubectl delete rs "$rs" -n monitoring --grace-period=0 --force 2>/dev/null || true
            fi
        done
    fi
    
    # Delete any remaining pods
    REMAINING_PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [ -n "$REMAINING_PODS" ]; then
        print_info "Cleaning up any remaining pods..."
        echo "$REMAINING_PODS" | while read pod; do
            if [ -n "$pod" ] && [ "$pod" != "NAME" ]; then
                kubectl delete pod "$pod" -n monitoring --grace-period=0 --force 2>/dev/null || true
            fi
        done
    fi
    
    # Check for existing PVCs and warn if they exist (they may have wrong permissions)
    EXISTING_PROMETHEUS_PVC=$(kubectl get pvc prometheus-pvc -n monitoring 2>/dev/null || echo "")
    EXISTING_GRAFANA_PVC=$(kubectl get pvc grafana-pvc -n monitoring 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_PROMETHEUS_PVC" ] || [ -n "$EXISTING_GRAFANA_PVC" ]; then
        print_warn "Existing PVCs found in monitoring namespace."
        print_warn "If you encounter permission errors, delete and recreate PVCs:"
        print_warn "  kubectl delete pvc prometheus-pvc grafana-pvc -n monitoring"
        print_warn "Then run this script again to recreate them with correct permissions."
        print_info "Continuing with deployment (PVCs will be reused if they exist)..."
    fi
    
    sleep 2
}

# Deploy Prometheus
deploy_prometheus() {
    print_info "Deploying Prometheus..."
    
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml"
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-deployment.yaml"
    
    print_info "Waiting for Prometheus to start (this may take 1-2 minutes)..."
    
    # Wait with progress updates
    local max_wait=120  # 2 minutes max
    local waited=0
    local check_interval=10
    local last_status=""
    
    while [ $waited -lt $max_wait ]; do
        # Check if pod is running AND ready
        local pod_phase=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
        local pod_ready=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        local pod_status="${pod_phase}"
        
        # Show status if it changed
        if [ "$pod_status" != "$last_status" ]; then
            if [ "$pod_ready" = "true" ]; then
                print_info "Prometheus pod status: ${pod_phase} (Ready)"
            else
                print_info "Prometheus pod status: ${pod_phase} (Not Ready)"
            fi
            last_status="$pod_status"
        fi
        
        # Check if pod is both Running AND Ready (1/1)
        if [ "$pod_phase" = "Running" ] && [ "$pod_ready" = "true" ]; then
            print_info "✓ Prometheus pod is running and ready!"
            break
        fi
        
        # Show progress every 30 seconds
        if [ $((waited % 30)) -eq 0 ] && [ $waited -gt 0 ]; then
            print_info "Still waiting... (${waited}s elapsed)"
            # Show pod details for debugging
            kubectl get pods -n monitoring -l app=prometheus 2>/dev/null | tail -1 || true
        fi
        
        sleep $check_interval
        waited=$((waited + check_interval))
    done
    
    if [ $waited -ge $max_wait ]; then
        print_warn "Prometheus deployment timed out after ${max_wait} seconds"
        print_info "Checking pod status for diagnostics..."
        kubectl get pods -n monitoring -l app=prometheus || true
        kubectl describe pod -n monitoring -l app=prometheus | tail -20 || true
        print_warn "Prometheus may still be starting. You can check with: kubectl get pods -n monitoring"
    else
        print_info "✓ Prometheus deployment ready!"
    fi
}

# Deploy Grafana
deploy_grafana() {
    print_info "Deploying Grafana..."
    
    # Deploy Grafana deployment (includes service, PVC, and ConfigMaps)
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/grafana-deployment.yaml"
    
    # Also apply separate service file if it exists (may be redundant but ensures consistency)
    if [ -f "${PROJECT_ROOT}/kubernetes/monitoring/grafana-service.yaml" ]; then
        kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/grafana-service.yaml"
    fi
    
    print_info "Waiting for Grafana to start (this may take 1-2 minutes)..."
    
    # Wait with progress updates
    local max_wait=120  # 2 minutes max
    local waited=0
    local check_interval=10
    local last_status=""
    
    while [ $waited -lt $max_wait ]; do
        # Check if pod is running AND ready
        local pod_phase=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
        local pod_ready=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        local pod_status="${pod_phase}"
        
        # Show status if it changed
        if [ "$pod_status" != "$last_status" ]; then
            if [ "$pod_ready" = "true" ]; then
                print_info "Grafana pod status: ${pod_phase} (Ready)"
            else
                print_info "Grafana pod status: ${pod_phase} (Not Ready)"
            fi
            last_status="$pod_status"
        fi
        
        # Check if pod is both Running AND Ready (1/1)
        if [ "$pod_phase" = "Running" ] && [ "$pod_ready" = "true" ]; then
            print_info "✓ Grafana pod is running and ready!"
            break
        fi
        
        # Show progress every 30 seconds
        if [ $((waited % 30)) -eq 0 ] && [ $waited -gt 0 ]; then
            print_info "Still waiting... (${waited}s elapsed)"
            # Show pod details for debugging
            kubectl get pods -n monitoring -l app=grafana 2>/dev/null | tail -1 || true
        fi
        
        sleep $check_interval
        waited=$((waited + check_interval))
    done
    
    if [ $waited -ge $max_wait ]; then
        print_warn "Grafana deployment timed out after ${max_wait} seconds"
        print_info "Checking pod status for diagnostics..."
        kubectl get pods -n monitoring -l app=grafana || true
        kubectl describe pod -n monitoring -l app=grafana | tail -20 || true
        print_warn "Grafana may still be starting. You can check with: kubectl get pods -n monitoring"
    else
        print_info "✓ Grafana deployment ready!"
    fi
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

# Show diagnostics if pods aren't starting
show_diagnostics() {
    print_info "Monitoring pod status:"
    kubectl get pods -n monitoring || true
    echo ""
    
    print_info "If pods are not starting, check:"
    print_info "  1. Cluster resources: kubectl top nodes"
    print_info "  2. Pod events: kubectl describe pod -n monitoring <pod-name>"
    print_info "  3. Pod logs: kubectl logs -n monitoring <pod-name>"
    print_info "  4. PVC status: kubectl get pvc -n monitoring"
    echo ""
}

# Main
main() {
    print_info "Setting up monitoring stack for Kubernetes..."
    print_warn "Note: This script is for Kubernetes only (GKE/Nautilus)"
    print_warn "For local docker-compose, monitoring is not available"
    echo ""
    
    check_kubectl
    create_namespace
    cleanup_existing_monitoring
    deploy_prometheus
    deploy_grafana
    
    echo ""
    print_info "Monitoring setup complete!"
    echo ""
    
    # Show current status
    show_diagnostics
    
    show_access
    echo ""
    print_info "To access monitoring from local machine:"
    print_info "  Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    print_info "  Grafana: kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo ""
    print_info "If pods are still starting, wait a few minutes and check:"
    print_info "  kubectl get pods -n monitoring"
}

main

