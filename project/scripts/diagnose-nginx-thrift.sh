#!/bin/bash

# Diagnose nginx-thrift crash issue

set -e

# Colors
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

echo ""
print_section "Diagnosing nginx-thrift CrashLoopBackOff"

NGINX_POD=$(kubectl get pods -l app=nginx-thrift | grep -v NAME | awk '{print $1}' | head -1)

if [ -z "$NGINX_POD" ]; then
    print_warn "No nginx-thrift pod found"
    exit 1
fi

print_info "Pod: $NGINX_POD"
echo ""

print_section "1. Current Pod Status"
kubectl get pod "$NGINX_POD" -o wide

echo ""
print_section "2. Recent Logs (Current Container)"
print_info "Trying to get recent logs..."
kubectl logs "$NGINX_POD" --tail=50 2>&1 || print_warn "Could not get current logs"

echo ""
print_section "3. Previous Container Logs (From Last Crash)"
print_info "Getting logs from previous crashed container..."
kubectl logs "$NGINX_POD" --previous --tail=50 2>&1 || print_warn "Could not get previous logs"

echo ""
print_section "4. Pod Events (Shows Errors)"
kubectl describe pod "$NGINX_POD" | grep -A 30 "Events:" || true

echo ""
print_section "5. Pod Status Details"
kubectl describe pod "$NGINX_POD" | grep -A 20 "State:" || true

echo ""
print_section "6. Container Status"
kubectl get pod "$NGINX_POD" -o jsonpath='{.status.containerStatuses[0]}' | python3 -m json.tool 2>/dev/null || \
kubectl get pod "$NGINX_POD" -o jsonpath='{.status.containerStatuses[0]}' || true

echo ""
print_section "7. Check ConfigMap Mounts"
print_info "Checking if required ConfigMaps exist..."
kubectl get configmap deathstarbench-config 2>&1 | head -3
kubectl get configmap nginx-lua-scripts 2>&1 | head -3
kubectl get configmap nginx-pages 2>&1 | head -3
kubectl get configmap nginx-gen-lua 2>&1 | head -3

echo ""
print_section "Summary"
print_warn "Check the logs and events above to see why nginx-thrift is crashing."
print_info "Common causes:"
echo "  - Missing ConfigMaps"
echo "  - Incorrect configuration files"
echo "  - Volume mount issues"
echo "  - Startup script errors"

