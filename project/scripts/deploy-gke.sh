#!/bin/bash

# Deployment Script for Google Kubernetes Engine (GKE)
#
# WHAT THIS DOES:
# This script automates the deployment of the entire application stack to GKE.
# It handles building Docker images, pushing them to Google Container Registry,
# creating the monitoring namespace, and deploying all Kubernetes resources.
#
# KEY CONCEPTS:
# - Docker image building: Packages your application into container images
# - Container Registry: Stores Docker images (GCR for GKE)
# - kubectl apply: Creates/updates Kubernetes resources
# - Namespaces: Logical separation of resources (monitoring vs application)
#
# PREREQUISITES:
# - gcloud CLI installed and authenticated
# - kubectl configured to connect to your GKE cluster
# - Docker installed and running
# - Appropriate permissions on GCP project

set -e  # Exit on any error

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
GKE_CLUSTER="${GKE_CLUSTER:-your-cluster-name}"
GKE_ZONE="${GKE_ZONE:-us-central1-a}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="gcr.io/${PROJECT_ID}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper function to print colored output
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
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    print_info "All prerequisites met!"
}

# Authenticate with GCP and configure Docker
setup_gcp() {
    print_info "Setting up GCP authentication..."
    
    # Set the project
    gcloud config set project "${PROJECT_ID}"
    
    # Get GKE credentials
    print_info "Getting GKE cluster credentials..."
    gcloud container clusters get-credentials "${GKE_CLUSTER}" --zone "${GKE_ZONE}"
    
    # Configure Docker to use gcloud as a credential helper
    print_info "Configuring Docker for GCR..."
    gcloud auth configure-docker
    
    print_info "GCP setup complete!"
}

# Build and push Docker images
build_and_push_images() {
    print_info "Building and pushing Docker images..."
    
    # Get the project root directory (parent of scripts directory)
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Build and push Nginx image
    print_info "Building Nginx image..."
    docker build -t "${REGISTRY}/nginx:${IMAGE_TAG}" "${PROJECT_ROOT}/docker/nginx"
    docker push "${REGISTRY}/nginx:${IMAGE_TAG}"
    
    # Build and push User Service image
    # NOTE: You'll need to adapt this based on your actual service structure
    # For DeathStarBench, you'll need to clone the repo and build from there
    print_warn "User service image build skipped - adapt this for your actual services"
    # docker build -t "${REGISTRY}/user-service:${IMAGE_TAG}" "${PROJECT_ROOT}/docker/user"
    # docker push "${REGISTRY}/user-service:${IMAGE_TAG}"
    
    print_info "Docker images built and pushed!"
}

# Create namespaces
create_namespaces() {
    print_info "Creating Kubernetes namespaces..."
    
    # Create monitoring namespace if it doesn't exist
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    print_info "Namespaces created!"
}

# Deploy ConfigMaps and Secrets
deploy_configs() {
    print_info "Deploying ConfigMaps and Secrets..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Deploy ConfigMaps
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/configmaps/"
    
    # Deploy Secrets
    # NOTE: In production, use proper secret management
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/configmaps/database-secret.yaml"
    
    print_info "ConfigMaps and Secrets deployed!"
}

# Deploy application services
deploy_application() {
    print_info "Deploying application services..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Update image references in deployment files
    # This is a simple approach - in production, use a templating tool like Helm
    print_warn "Make sure to update image references in deployment YAML files!"
    
    # Deploy services first (they're lightweight)
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/services/"
    
    # Deploy deployments
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/"
    
    # Wait for deployments to be ready
    print_info "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/nginx-deployment || true
    
    print_info "Application services deployed!"
}

# Deploy autoscaling
deploy_autoscaling() {
    print_info "Deploying autoscaling configurations..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Deploy HPA
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/"
    
    print_info "Autoscaling configurations deployed!"
}

# Deploy monitoring
deploy_monitoring() {
    print_info "Deploying monitoring stack..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Deploy Prometheus
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-configmap.yaml"
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/prometheus-deployment.yaml"
    
    # Wait for Prometheus to be ready
    print_info "Waiting for Prometheus to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus -n monitoring || true
    
    # Deploy Grafana
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/grafana-deployment.yaml"
    
    # Wait for Grafana to be ready
    print_info "Waiting for Grafana to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring || true
    
    print_info "Monitoring stack deployed!"
}

# Get service endpoints
show_endpoints() {
    print_info "Service endpoints:"
    
    # Get Nginx LoadBalancer IP
    NGINX_IP=$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
    print_info "Nginx (Application): http://${NGINX_IP}"
    
    # Get Grafana LoadBalancer IP
    GRAFANA_IP=$(kubectl get service grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
    print_info "Grafana (Monitoring): http://${GRAFANA_IP}:3000"
    print_info "  Default credentials: admin/admin"
    
    # Get Prometheus endpoint (ClusterIP, so we'll show port-forward command)
    print_info "Prometheus: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    print_info "  Then access at: http://localhost:9090"
}

# Main deployment flow
main() {
    print_info "Starting GKE deployment..."
    print_info "Project: ${PROJECT_ID}"
    print_info "Cluster: ${GKE_CLUSTER}"
    print_info "Zone: ${GKE_ZONE}"
    
    check_prerequisites
    setup_gcp
    create_namespaces
    deploy_configs
    build_and_push_images
    deploy_application
    deploy_autoscaling
    deploy_monitoring
    
    print_info "Deployment complete!"
    echo ""
    show_endpoints
    echo ""
    print_info "To check deployment status:"
    print_info "  kubectl get pods"
    print_info "  kubectl get services"
    print_info "  kubectl get hpa"
}

# Run main function
main

