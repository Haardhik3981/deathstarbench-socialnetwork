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
PROJECT_ID=$(gcloud config get-value project) # Automatically get project ID
GKE_CLUSTER="${GKE_CLUSTER:-social-network-cluster}"
GKE_ZONE="${GKE_ZONE:-us-central1-a}"
GCP_REGION="us-central1" # Region for Artifact Registry
ARTIFACT_REPO="social-network-images"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}"

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
    print_info "Configuring Docker for Artifact Registry..."
    gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev"
    
    # Create Artifact Registry repository if it doesn't exist
    print_info "Checking/creating Artifact Registry repository..."
    if ! gcloud artifacts repositories describe "${ARTIFACT_REPO}" \
        --location="${GCP_REGION}" \
        --repository-format=docker &>/dev/null; then
        print_info "Creating Artifact Registry repository: ${ARTIFACT_REPO}"
        gcloud artifacts repositories create "${ARTIFACT_REPO}" \
            --repository-format=docker \
            --location="${GCP_REGION}" \
            --description="Docker images for social network microservices"
    else
        print_info "Artifact Registry repository already exists: ${ARTIFACT_REPO}"
    fi
    
    print_info "GCP setup complete!"
}

# Build and push Docker images
build_and_push_images() {
    print_info "Building and pushing Docker images..."
    
    # Get the project root directory (parent of scripts directory)
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Point to the actual DeathStarBench source directory
    # This assumes project/ and socialNetwork/ are siblings in the same parent directory
    DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"
    
    if [ ! -f "${DSB_ROOT}/Dockerfile" ]; then
        print_error "DeathStarBench source not found at ${DSB_ROOT}"
        print_error "Expected to find: ${DSB_ROOT}/Dockerfile"
        print_info "Make sure socialNetwork/ directory exists as a sibling to project/"
        exit 1
    fi
    
    print_info "Found DeathStarBench source at: ${DSB_ROOT}"
    
    # We will pull the pre-built image from Docker Hub, re-tag it for our registry, and push it.
    # This avoids the slow and memory-intensive local build process.
    print_info "Pulling pre-built image from Docker Hub..."
    if ! docker pull deathstarbench/social-network-microservices:latest; then
        print_error "Failed to pull image from Docker Hub: deathstarbench/social-network-microservices:latest"
        print_error "Please check your internet connection and Docker Hub access."
        exit 1
    fi
    
    print_info "Re-tagging image for Google Artifact Registry..."
    docker tag deathstarbench/social-network-microservices:latest "${REGISTRY}/social-network-microservices:${IMAGE_TAG}"
    
    print_info "Pushing image to Google Artifact Registry..."
    if ! docker push "${REGISTRY}/social-network-microservices:${IMAGE_TAG}"; then
        print_error "Failed to push image to Artifact Registry: ${REGISTRY}/social-network-microservices:${IMAGE_TAG}"
        print_error "Please check your GCP permissions and Artifact Registry setup."
        exit 1
    fi
    
    print_info "Docker images built and pushed!"
    print_info "Image available at: ${REGISTRY}/social-network-microservices:${IMAGE_TAG}"
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
    
    # Note: DeathStarBench doesn't use database secrets in the same way
    # Configuration is in service-config.json ConfigMap
    
    print_info "ConfigMaps and Secrets deployed!"
}

# Deploy application services
deploy_application() {
    print_info "Deploying application services..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Create temporary directory for modified YAML files
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT
    
    print_info "Updating image references in Kubernetes deployment files..."
    
    # Copy deployment files to temp directory and update image references
    # We need to replace both the old Docker Hub reference AND any hardcoded registry paths
    # Preserve directory structure in temp directory
    find "${PROJECT_ROOT}/kubernetes/deployments" -name "*.yaml" -type f | while read -r file; do
        # Get relative path from deployments directory to preserve structure
        rel_path="${file#${PROJECT_ROOT}/kubernetes/deployments/}"
        target_dir="${TEMP_DIR}/$(dirname "$rel_path")"
        mkdir -p "$target_dir"
        
        # Skip nginx-thrift-deployment.yaml (uses different image)
        if [[ "$(basename "$file")" == "nginx-thrift-deployment.yaml" ]]; then
            cp "$file" "${TEMP_DIR}/${rel_path}"
        else
            # Create temp file with updated image references
            # Replace: Docker Hub reference, hardcoded Artifact Registry paths with any project ID
            # Pattern matches: us-central1-docker.pkg.dev/<any-project-id>/social-network-images/social-network-microservices:<any-tag>
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS sed - escape dots and use character class for project ID
                sed -E \
                    -e "s|image: deathstarbench/social-network-microservices:latest|image: ${REGISTRY}/social-network-microservices:${IMAGE_TAG}|g" \
                    -e "s|image: us-central1-docker\.pkg\.dev/[a-zA-Z0-9_-]+/social-network-images/social-network-microservices:[^[:space:]]+|image: ${REGISTRY}/social-network-microservices:${IMAGE_TAG}|g" \
                    "$file" > "${TEMP_DIR}/${rel_path}"
            else
                # Linux sed - escape dots and use character class for project ID
                sed -E \
                    -e "s|image: deathstarbench/social-network-microservices:latest|image: ${REGISTRY}/social-network-microservices:${IMAGE_TAG}|g" \
                    -e "s|image: us-central1-docker\.pkg\.dev/[a-zA-Z0-9_-]+/social-network-images/social-network-microservices:[^[:space:]]+|image: ${REGISTRY}/social-network-microservices:${IMAGE_TAG}|g" \
                    "$file" > "${TEMP_DIR}/${rel_path}"
            fi
        fi
    done
    
    print_info "Image references updated to use: ${REGISTRY}/social-network-microservices:${IMAGE_TAG}"
    
    # Deploy services first (they're lightweight)
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/services/"
    
    # Deploy deployments from temp directory
    kubectl apply -f "${TEMP_DIR}/"
    
    # Wait for deployments to be ready
    print_info "Waiting for deployments to be ready..."
    # Wait for nginx-thrift (the gateway)
    kubectl wait --for=condition=available --timeout=300s deployment/nginx-thrift-deployment || true
    # Wait for a few key services
    kubectl wait --for=condition=available --timeout=300s deployment/user-service-deployment || true
    
    print_info "Application services deployed!"
}

# Deploy autoscaling
deploy_autoscaling() {
    print_info "Deploying autoscaling configurations..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Deploy the main HPA and VPA configurations.
    # We explicitly apply only the intended files to avoid conflicts from experimental configs.
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/user-service-hpa.yaml"
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/user-service-vpa.yaml"
    
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
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/monitoring/grafana-service.yaml"
    
    # Wait for Grafana to be ready
    print_info "Waiting for Grafana to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/grafana -n monitoring || true
    
    print_info "Monitoring stack deployed!"
}

# Get service endpoints
show_endpoints() {
    print_info "Service endpoints:"
    
    # Get Nginx-Thrift LoadBalancer IP
    NGINX_IP=$(kubectl get service nginx-thrift-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending...")
    print_info "Nginx-Thrift (Application Gateway): http://${NGINX_IP}:8080"
    
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
    print_info "Registry: ${REGISTRY}"
    
    check_prerequisites
    setup_gcp
    create_namespaces
    # Build and push images BEFORE deploying configs to ensure image is available
    build_and_push_images
    deploy_configs
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
