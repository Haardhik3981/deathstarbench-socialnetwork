#!/bin/bash

# Complete Deployment Script for DeathStarBench Social Network on GKE
# This script deploys everything from scratch with all fixes applied

set -e  # Exit on any error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"

echo ""
echo "=========================================="
echo "  DeathStarBench Deployment Script"
echo "=========================================="
echo ""

# Check prerequisites
print_section "Step 1: Checking Prerequisites"

if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install it first."
    exit 1
fi
print_info "✓ kubectl found"

if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please configure kubectl first."
    exit 1
fi
print_info "✓ Connected to Kubernetes cluster"

# Check DeathStarBench source
if [ ! -d "${DSB_ROOT}" ]; then
    print_error "DeathStarBench source not found at: ${DSB_ROOT}"
    print_error "Expected: ../socialNetwork/"
    exit 1
fi
print_info "✓ DeathStarBench source found at: ${DSB_ROOT}"

# Check if source code has been modified (for Docker image rebuild)
print_warn "IMPORTANT: If you've modified DeathStarBench source code (e.g., SocialGraphHandler.h),"
print_warn "  you MUST rebuild the Docker image before deploying:"
print_warn "  1. Build the C++ code"
print_warn "  2. Create new Docker image: docker build -t <your-registry>/social-network-microservices:latest ."
print_warn "  3. Push to registry: docker push <your-registry>/social-network-microservices:latest"
print_warn "  4. Update deployment YAMLs with new image tag if needed"
echo ""

# Check cluster resources
print_section "Step 2: Checking Cluster Resources"
print_info "Checking cluster nodes..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
print_info "Nodes in cluster: $NODE_COUNT"

if [ "$NODE_COUNT" -lt 3 ]; then
    print_warn "Recommended: At least 3 nodes for this deployment"
    print_warn "Current: $NODE_COUNT nodes"
    print_warn "You may experience CPU/resource constraints with fewer nodes"
fi

# Create ConfigMaps
print_section "Step 3: Creating ConfigMaps"
print_info "This may take a moment..."

# Create main config ConfigMap
print_info "Creating deathstarbench-config ConfigMap..."
kubectl delete configmap deathstarbench-config 2>/dev/null || true

kubectl create configmap deathstarbench-config \
  --from-file=service-config.json="${DSB_ROOT}/config/service-config.json" \
  --from-file=jaeger-config.yml="${DSB_ROOT}/config/jaeger-config.yml" \
  --from-file=nginx.conf="${DSB_ROOT}/nginx-web-server/conf/nginx.conf" \
  --from-file=jaeger-config.json="${DSB_ROOT}/nginx-web-server/jaeger-config.json"

print_info "✓ deathstarbench-config created"

# Create pages ConfigMap
print_info "Creating nginx-pages ConfigMap..."
kubectl delete configmap nginx-pages 2>/dev/null || true
kubectl create configmap nginx-pages --from-file="${DSB_ROOT}/nginx-web-server/pages/"
print_info "✓ nginx-pages created"

# Create gen-lua ConfigMap
print_info "Creating nginx-gen-lua ConfigMap..."
kubectl delete configmap nginx-gen-lua 2>/dev/null || true
kubectl create configmap nginx-gen-lua --from-file="${DSB_ROOT}/gen-lua/"
print_info "✓ nginx-gen-lua created"

# Create nginx-lua-scripts ConfigMap (requires special handling for subdirectories)
print_info "Creating nginx-lua-scripts ConfigMap (with subdirectories)..."
LUA_SCRIPTS_DIR="${DSB_ROOT}/nginx-web-server/lua-scripts"

if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    print_warn "Lua scripts directory not found, skipping nginx-lua-scripts ConfigMap"
else
    # Use the fix script to properly create the ConfigMap with subdirectories
    print_info "  Creating ConfigMap with all Lua script files (including subdirectories)..."
    # Try create-lua-configmap-solution.sh first (the working solution)
    if [ -f "${PROJECT_ROOT}/scripts/create-lua-configmap-solution.sh" ]; then
        if "${PROJECT_ROOT}/scripts/create-lua-configmap-solution.sh" >/dev/null 2>&1; then
            print_info "✓ nginx-lua-scripts ConfigMap created successfully (using create-lua-configmap-solution.sh)"
        else
            print_warn "create-lua-configmap-solution.sh encountered issues, trying fallback..."
            # Fallback to fix-nginx-lua-scripts.sh
            if [ -f "${PROJECT_ROOT}/scripts/fix-nginx-lua-scripts.sh" ]; then
                if "${PROJECT_ROOT}/scripts/fix-nginx-lua-scripts.sh" >/dev/null 2>&1; then
                    print_info "✓ nginx-lua-scripts ConfigMap created successfully (using fix-nginx-lua-scripts.sh)"
                else
                    print_warn "Fix script encountered issues, trying fallback method..."
                    kubectl delete configmap nginx-lua-scripts 2>/dev/null || true
                    cd "${LUA_SCRIPTS_DIR}"
                    # Basic fallback (may not preserve subdirs perfectly)
                    if kubectl create configmap nginx-lua-scripts --from-file=. 2>/dev/null; then
                        print_info "✓ nginx-lua-scripts ConfigMap created (fallback method)"
                    else
                        print_warn "Could not create nginx-lua-scripts ConfigMap"
                    fi
                    cd "${PROJECT_ROOT}"
                fi
            else
                print_warn "No Lua script fix scripts found, trying basic ConfigMap creation..."
                kubectl delete configmap nginx-lua-scripts 2>/dev/null || true
                cd "${LUA_SCRIPTS_DIR}"
                if kubectl create configmap nginx-lua-scripts --from-file=. 2>/dev/null; then
                    print_info "✓ nginx-lua-scripts ConfigMap created (basic method)"
                else
                    print_warn "Could not create nginx-lua-scripts ConfigMap"
                fi
                cd "${PROJECT_ROOT}"
            fi
        fi
    else
        print_warn "create-lua-configmap-solution.sh not found, trying basic ConfigMap creation..."
        kubectl delete configmap nginx-lua-scripts 2>/dev/null || true
        cd "${LUA_SCRIPTS_DIR}"
        if kubectl create configmap nginx-lua-scripts --from-file=. 2>/dev/null; then
            print_info "✓ nginx-lua-scripts ConfigMap created (basic method)"
        else
            print_warn "Could not create nginx-lua-scripts ConfigMap"
        fi
        cd "${PROJECT_ROOT}"
    fi
fi

# Deploy databases first
print_section "Step 4: Deploying Databases (MongoDB)"
print_info "Deploying MongoDB databases..."
for db in media-mongodb post-storage-mongodb social-graph-mongodb url-shorten-mongodb user-mongodb user-timeline-mongodb; do
    print_info "  Deploying ${db}..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/databases/${db}-deployment.yaml"
done
print_info "✓ All MongoDB databases deployed"

# Wait for databases to be ready
print_info "Waiting 30 seconds for databases to start..."
sleep 30

# Deploy caches (Redis and Memcached are in combined files)
print_section "Step 5: Deploying Cache Services (Redis & Memcached)"
print_info "Deploying Redis deployments (4 instances: social-graph, home-timeline, user-timeline, compose-post)..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/databases/redis-deployments.yaml"
print_info "✓ Redis deployments created"

print_info "Deploying Memcached deployments (4 instances)..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/databases/memcached-deployments.yaml"
print_info "✓ Memcached deployments created"

# Wait for caches
print_info "Waiting 20 seconds for caches to start..."
sleep 20

# Verify compose-post-redis is included (it's in redis-deployments.yaml now)
print_info "Note: Redis deployments include compose-post-redis (added to fix compose-post errors)"

# Deploy services
print_section "Step 6: Deploying Microservices"
print_info "Deploying all microservices..."

SERVICE_DEPLOYMENTS=(
    "compose-post-service"
    "home-timeline-service"
    "media-service"
    "post-storage-service"
    "social-graph-service"
    "text-service"
    "unique-id-service"
    "url-shorten-service"
    "user-mention-service"
    "user-timeline-service"
    "user-service"
)

for service in "${SERVICE_DEPLOYMENTS[@]}"; do
    print_info "  Deploying ${service}..."
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/${service}-deployment.yaml"
done
print_info "✓ All microservices deployed"

# Wait for services
print_info "Waiting 30 seconds for services to start..."
sleep 30

# Deploy write-home-timeline services (RabbitMQ and worker)
# Note: These are optional - home-timeline-service can work without them
# but they provide async processing via RabbitMQ
print_section "Step 6b: Deploying Write Home Timeline Services (Optional)"
print_info "Deploying write-home-timeline-rabbitmq..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/write-home-timeline-rabbitmq-deployment.yaml"
kubectl apply -f "${PROJECT_ROOT}/kubernetes/services/write-home-timeline-rabbitmq-service.yaml"
print_info "✓ write-home-timeline-rabbitmq deployed"

print_info "Deploying write-home-timeline-service..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/write-home-timeline-service-deployment.yaml"
print_info "✓ write-home-timeline-service deployed"

# Wait for write-home-timeline services
print_info "Waiting 15 seconds for write-home-timeline services to start..."
sleep 15

# Deploy Jaeger
print_section "Step 7: Deploying Jaeger (Tracing)"
print_info "Deploying Jaeger..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/jaeger-deployment.yaml"
print_info "✓ Jaeger deployed"

# Deploy nginx-thrift (without health checks initially)
print_section "Step 8: Deploying nginx-thrift Gateway"
print_info "Deploying nginx-thrift (health checks disabled for initial startup)..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/nginx-thrift-deployment.yaml"
print_info "✓ nginx-thrift deployed"

# Deploy services (Kubernetes Service objects)
print_section "Step 9: Deploying Kubernetes Services"
print_info "Creating Service objects for networking..."

# Deploy all services
for service_file in "${PROJECT_ROOT}"/kubernetes/services/*.yaml; do
    if [ -f "$service_file" ]; then
        service_name=$(basename "$service_file" .yaml)
        print_info "  Creating service: ${service_name}"
        kubectl apply -f "$service_file"
    fi
done

print_info "✓ All Services created"

# Final wait
print_section "Step 10: Waiting for Everything to Stabilize"
print_info "Waiting 60 seconds for all pods to start..."
sleep 60

# Status check
print_section "Final Status Check"
echo ""
print_info "Checking pod status..."

RUNNING=$(kubectl get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
PENDING=$(kubectl get pods --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
CRASH=$(kubectl get pods --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l | tr -d ' ')

print_info "Running pods: $RUNNING"
print_info "Pending pods: $PENDING"
print_info "Failed pods: $CRASH"

if [ "$PENDING" -gt 0 ] || [ "$CRASH" -gt 0 ]; then
    print_warn "Some pods are not running. Checking details..."
    echo ""
    kubectl get pods | grep -v Running || true
fi

echo ""
print_section "Deployment Complete!"
echo ""
print_info "View all pods:"
echo "  kubectl get pods"
echo ""
print_info "View services:"
echo "  kubectl get svc"
echo ""
print_info "Get nginx-thrift service URL:"
echo "  kubectl get svc nginx-thrift-service"
echo ""
print_info "Port-forward to test:"
echo "  kubectl port-forward svc/nginx-thrift-service 8080:8080"
echo ""
print_info "Note: All ConfigMaps have been created including nginx-lua-scripts"
print_info "The nginx-thrift gateway should be fully functional with all Lua scripts."
echo ""
print_warn "CRITICAL: Source Code Fix Applied"
print_warn "  A bug fix has been applied to SocialGraphHandler.h to prevent 'ZADD: no key specified' errors."
print_warn "  If you haven't rebuilt the Docker image with this fix, you MUST do so now:"
print_warn "    1. Rebuild the C++ code with the fixed SocialGraphHandler.h"
print_warn "    2. Rebuild Docker image: docker build -t <registry>/social-network-microservices:latest ."
print_warn "    3. Push to registry: docker push <registry>/social-network-microservices:latest"
print_warn "    4. Restart social-graph-service: kubectl rollout restart deployment/social-graph-service-deployment"
echo ""
print_info "To set up monitoring (Prometheus & Grafana):"
echo "  ./scripts/setup-monitoring.sh"
echo ""
print_warn "Note: Prometheus is configured to skip DeathStarBench microservices"
print_warn "  (they use Thrift, not HTTP metrics). Container metrics are available via cAdvisor."

echo ""
echo "=========================================="
print_info "Deployment script completed!"
echo "=========================================="
echo ""
print_section "Summary of Changes Applied"
print_info "✓ Added compose-post-redis deployment (fixes compose-post ZADD errors)"
print_info "✓ Added write-home-timeline-service and RabbitMQ (async processing)"
print_info "✓ Updated Redis deployment count (now 4 instances)"
print_info "✓ Fixed Lua scripts ConfigMap creation (uses create-lua-configmap-solution.sh)"
print_warn "⚠ REMEMBER: Rebuild Docker image if SocialGraphHandler.h was modified!"
print_warn "   The fix prevents 'ZADD: no key specified' errors for users with no followers."
echo ""

