#!/bin/bash

# Verification Script for DeathStarBench Social Network Deployment
# This script checks that all pods, services, and ConfigMaps are ready

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "  $1"
}

# Track overall status
ERRORS=0
WARNINGS=0

echo ""
echo "=========================================="
echo "  DeathStarBench Deployment Verification"
echo "=========================================="
echo ""

# Check kubectl connection
print_section "Step 1: Checking kubectl Connection"
if kubectl cluster-info &> /dev/null; then
    print_success "Connected to Kubernetes cluster"
    CLUSTER_INFO=$(kubectl cluster-info | head -n 1)
    print_info "Cluster: $CLUSTER_INFO"
else
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

echo ""

# Check ConfigMaps
print_section "Step 2: Checking ConfigMaps"
REQUIRED_CONFIGMAPS=(
    "deathstarbench-config"
    "nginx-pages"
    "nginx-gen-lua"
)

for cm in "${REQUIRED_CONFIGMAPS[@]}"; do
    if kubectl get configmap "$cm" &> /dev/null; then
        print_success "ConfigMap '$cm' exists"
    else
        print_error "ConfigMap '$cm' is missing"
        ((ERRORS++))
    fi
done

# Check nginx-lua-scripts ConfigMaps (should have multiple)
LUA_CONFIGMAPS=$(kubectl get configmap -o name 2>/dev/null | grep "nginx-lua-scripts" | wc -l | tr -d ' ')
if [ "$LUA_CONFIGMAPS" -gt 0 ]; then
    print_success "nginx-lua-scripts ConfigMaps exist ($LUA_CONFIGMAPS found)"
else
    print_warn "nginx-lua-scripts ConfigMaps not found (may cause nginx-thrift issues)"
    ((WARNINGS++))
fi

echo ""

# Check MongoDB Deployments
print_section "Step 3: Checking MongoDB Deployments"
MONGODB_DEPLOYMENTS=(
    "media-mongodb-deployment"
    "post-storage-mongodb-deployment"
    "social-graph-mongodb-deployment"
    "url-shorten-mongodb-deployment"
    "user-mongodb-deployment"
    "user-timeline-mongodb-deployment"
)

for deployment in "${MONGODB_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deployment" &> /dev/null; then
        READY=$(kubectl get deployment "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment "$deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
            print_success "MongoDB '$deployment' is ready ($READY/$DESIRED)"
        else
            print_warn "MongoDB '$deployment' is not ready ($READY/$DESIRED)"
            ((WARNINGS++))
        fi
    else
        print_error "MongoDB deployment '$deployment' not found"
        ((ERRORS++))
    fi
done

echo ""

# Check Redis Deployments
print_section "Step 4: Checking Redis Deployments"
REDIS_DEPLOYMENTS=(
    "social-graph-redis-deployment"
    "home-timeline-redis-deployment"
    "user-timeline-redis-deployment"
    "compose-post-redis-deployment"
)

for deployment in "${REDIS_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deployment" &> /dev/null; then
        READY=$(kubectl get deployment "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment "$deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
            print_success "Redis '$deployment' is ready ($READY/$DESIRED)"
        else
            print_warn "Redis '$deployment' is not ready ($READY/$DESIRED)"
            ((WARNINGS++))
        fi
    else
        print_error "Redis deployment '$deployment' not found"
        ((ERRORS++))
    fi
done

echo ""

# Check Memcached Deployments
print_section "Step 5: Checking Memcached Deployments"
MEMCACHED_DEPLOYMENTS=(
    "media-memcached-deployment"
    "post-storage-memcached-deployment"
    "url-shorten-memcached-deployment"
    "user-memcached-deployment"
)

for deployment in "${MEMCACHED_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deployment" &> /dev/null; then
        READY=$(kubectl get deployment "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment "$deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
            print_success "Memcached '$deployment' is ready ($READY/$DESIRED)"
        else
            print_warn "Memcached '$deployment' is not ready ($READY/$DESIRED)"
            ((WARNINGS++))
        fi
    else
        print_error "Memcached deployment '$deployment' not found"
        ((ERRORS++))
    fi
done

echo ""

# Check Microservice Deployments
print_section "Step 6: Checking Microservice Deployments"
MICROSERVICE_DEPLOYMENTS=(
    "compose-post-service-deployment"
    "home-timeline-service-deployment"
    "media-service-deployment"
    "post-storage-service-deployment"
    "social-graph-service-deployment"
    "text-service-deployment"
    "unique-id-service-deployment"
    "url-shorten-service-deployment"
    "user-mention-service-deployment"
    "user-timeline-service-deployment"
    "user-service-deployment"
)

for deployment in "${MICROSERVICE_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deployment" &> /dev/null; then
        READY=$(kubectl get deployment "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(kubectl get deployment "$deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
            print_success "Microservice '$deployment' is ready ($READY/$DESIRED)"
        else
            print_warn "Microservice '$deployment' is not ready ($READY/$DESIRED)"
            ((WARNINGS++))
        fi
    else
        print_error "Microservice deployment '$deployment' not found"
        ((ERRORS++))
    fi
done

echo ""

# Check Write Home Timeline Services (Optional)
print_section "Step 7: Checking Write Home Timeline Services (Optional)"
if kubectl get deployment "write-home-timeline-rabbitmq-deployment" &> /dev/null; then
    READY=$(kubectl get deployment "write-home-timeline-rabbitmq-deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "write-home-timeline-rabbitmq-deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
        print_success "write-home-timeline-rabbitmq is ready ($READY/$DESIRED)"
    else
        print_warn "write-home-timeline-rabbitmq is not ready ($READY/$DESIRED) - optional"
        ((WARNINGS++))
    fi
else
    print_warn "write-home-timeline-rabbitmq-deployment not found - optional"
    ((WARNINGS++))
fi

if kubectl get deployment "write-home-timeline-service-deployment" &> /dev/null; then
    READY=$(kubectl get deployment "write-home-timeline-service-deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "write-home-timeline-service-deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    # Handle empty values
    READY=${READY:-0}
    DESIRED=${DESIRED:-0}
    if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
        print_success "write-home-timeline-service is ready ($READY/$DESIRED)"
    else
        print_warn "write-home-timeline-service is not ready ($READY/$DESIRED) - optional"
        ((WARNINGS++))
    fi
else
    print_warn "write-home-timeline-service-deployment not found - optional"
    ((WARNINGS++))
fi

echo ""

# Check nginx-thrift Gateway
print_section "Step 8: Checking nginx-thrift Gateway"
if kubectl get deployment "nginx-thrift-deployment" &> /dev/null; then
    READY=$(kubectl get deployment "nginx-thrift-deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "nginx-thrift-deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
        print_success "nginx-thrift-deployment is ready ($READY/$DESIRED)"
    else
        print_error "nginx-thrift-deployment is not ready ($READY/$DESIRED)"
        ((ERRORS++))
    fi
else
    print_error "nginx-thrift-deployment not found"
    ((ERRORS++))
fi

# Check nginx-thrift Service
if kubectl get service "nginx-thrift" &> /dev/null; then
    print_success "nginx-thrift service exists"
    SERVICE_TYPE=$(kubectl get service "nginx-thrift" -o jsonpath='{.spec.type}' 2>/dev/null)
    print_info "Service type: $SERVICE_TYPE"
    if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
        EXTERNAL_IP=$(kubectl get service "nginx-thrift" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [ -n "$EXTERNAL_IP" ]; then
            print_success "LoadBalancer IP: $EXTERNAL_IP"
        else
            print_warn "LoadBalancer IP not yet assigned (may take 1-2 minutes)"
            ((WARNINGS++))
        fi
    fi
else
    print_error "nginx-thrift service not found"
    ((ERRORS++))
fi

echo ""

# Check Jaeger
print_section "Step 9: Checking Jaeger (Tracing)"
if kubectl get deployment "jaeger-deployment" &> /dev/null; then
    READY=$(kubectl get deployment "jaeger-deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "jaeger-deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
        print_success "jaeger-deployment is ready ($READY/$DESIRED)"
    else
        print_warn "jaeger-deployment is not ready ($READY/$DESIRED) - optional"
        ((WARNINGS++))
    fi
else
    print_warn "jaeger-deployment not found - optional"
    ((WARNINGS++))
fi

echo ""

# Check Pod Status Summary
print_section "Step 10: Pod Status Summary"
TOTAL_PODS=$(kubectl get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
RUNNING_PODS=$(kubectl get pods --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
PENDING_PODS=$(kubectl get pods --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
FAILED_PODS=$(kubectl get pods --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l | tr -d ' ')
CRASH_LOOP_PODS=$(kubectl get pods --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" || echo "0")

print_info "Total pods: $TOTAL_PODS"
print_info "Running: $RUNNING_PODS"
print_info "Pending: $PENDING_PODS"
print_info "Failed: $FAILED_PODS"
print_info "CrashLoopBackOff: $CRASH_LOOP_PODS"

if [ "$CRASH_LOOP_PODS" -gt 0 ]; then
    print_warn "Pods in CrashLoopBackOff:"
    kubectl get pods | grep "CrashLoopBackOff" | awk '{print "  - " $1}' || true
    ((WARNINGS++))
fi

echo ""

# Final Summary
print_section "Verification Summary"
echo ""

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    print_success "All critical components are ready!"
    echo ""
    print_info "You can now run k6 tests:"
    echo "  kubectl port-forward svc/nginx-thrift 8080:8080"
    echo "  k6 run k6-tests/constant-load.js"
    exit 0
elif [ "$ERRORS" -eq 0 ]; then
    print_warn "All critical components are ready, but there are $WARNINGS warning(s)"
    echo ""
    print_info "You can run k6 tests, but some optional components may not be ready"
    exit 0
else
    print_error "Found $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    print_info "Please fix the errors before running tests"
    echo ""
    print_info "To check pod logs:"
    echo "  kubectl logs <pod-name>"
    echo ""
    print_info "To check pod status:"
    echo "  kubectl describe pod <pod-name>"
    exit 1
fi

