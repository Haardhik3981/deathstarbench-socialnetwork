#!/bin/bash

# Check nginx-thrift issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

NGINX_POD=$(kubectl get pods | grep nginx-thrift | grep Running | head -1 | awk '{print $1}')

if [ -z "$NGINX_POD" ] || [ "$NGINX_POD" == "NAME" ]; then
    print_info "No running nginx-thrift pod found. Checking crashed pod..."
    NGINX_POD=$(kubectl get pods | grep nginx-thrift | grep -v Terminating | head -1 | awk '{print $1}')
fi

if [ -n "$NGINX_POD" ] && [ "$NGINX_POD" != "NAME" ]; then
    print_info "Checking pod: $NGINX_POD"
    echo ""
    
    print_info "=== Pod Logs ==="
    kubectl logs "$NGINX_POD" --tail=50 2>&1 | head -50
    
    echo ""
    print_info "=== Pod Events ==="
    kubectl describe pod "$NGINX_POD" | grep -A 10 "Events:" | tail -15
    
    echo ""
    print_info "=== Volume Mounts ==="
    kubectl describe pod "$NGINX_POD" | grep -A 15 "Mounts:"
else
    print_info "No nginx-thrift pods found"
fi

echo ""
print_info "=== ConfigMap Check ==="
print_info "Checking if required ConfigMaps exist:"
kubectl get configmap | grep -E "nginx-lua-scripts|nginx-pages|nginx-gen-lua|deathstarbench-config"

