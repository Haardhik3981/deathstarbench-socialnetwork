#!/bin/bash

# Deep diagnostic for nginx-thrift - checks what's actually happening inside the container

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_section() { echo -e "${BLUE}=== $1 ===${NC}"; }

print_section "Deep nginx-thrift Diagnostic"

# Get pod name
POD_NAME=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    print_error "No nginx-thrift pod found!"
    exit 1
fi

print_info "Pod: $POD_NAME"
echo ""

# 1. Check what's actually running in the container
print_section "1. Processes in Container"
print_info "Listing all running processes..."
kubectl exec "$POD_NAME" -- ps aux 2>/dev/null || print_warn "Cannot exec into pod - may not be ready"
echo ""

# 2. Check if nginx/openresty is actually running
print_section "2. Nginx/OpenResty Process Check"
print_info "Looking for nginx/openresty processes..."
kubectl exec "$POD_NAME" -- sh -c "pgrep -a nginx || pgrep -a openresty || echo 'No nginx/openresty process found'" 2>/dev/null || print_warn "Cannot check processes"
echo ""

# 3. Check what's listening on ports
print_section "3. Port Listeners"
print_info "Checking what's listening on ports..."
kubectl exec "$POD_NAME" -- sh -c "netstat -tlnp 2>/dev/null || ss -tlnp 2>/dev/null || lsof -i -P -n 2>/dev/null || echo 'Cannot check ports (netstat/ss/lsof not available)'" 2>/dev/null || print_warn "Cannot check ports"
echo ""

# 4. Check container entrypoint/command
print_section "4. Container Entrypoint/Command"
print_info "Checking how container was started..."
kubectl get pod "$POD_NAME" -o jsonpath='{.spec.containers[0].command}' 2>/dev/null && echo "" || print_warn "Cannot get command"
kubectl get pod "$POD_NAME" -o jsonpath='{.spec.containers[0].args}' 2>/dev/null && echo "" || print_warn "Cannot get args"
echo ""

# 5. Check if nginx.conf exists and is readable
print_section "5. Nginx Configuration"
print_info "Checking if nginx.conf exists..."
kubectl exec "$POD_NAME" -- ls -la /etc/nginx/nginx.conf 2>/dev/null || print_warn "nginx.conf not found at expected location"
echo ""

print_info "Checking nginx.conf content (first 50 lines)..."
kubectl exec "$POD_NAME" -- head -50 /etc/nginx/nginx.conf 2>/dev/null || print_warn "Cannot read nginx.conf"
echo ""

# 6. Check mounted volumes/ConfigMaps
print_section "6. Volume Mounts Status"
print_info "Checking if ConfigMap mounts exist..."
kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/ 2>/dev/null | head -20 || print_warn "Cannot list nginx directory"
echo ""

print_info "Checking lua-scripts directory..."
kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/ 2>/dev/null | head -10 || print_warn "lua-scripts directory not accessible"
echo ""

# 7. Try to manually test nginx
print_section "7. Manual Nginx Test"
print_info "Checking nginx executable..."
kubectl exec "$POD_NAME" -- which nginx 2>/dev/null || kubectl exec "$POD_NAME" -- which openresty 2>/dev/null || print_warn "nginx/openresty executable not found"
echo ""

print_info "Testing nginx configuration..."
kubectl exec "$POD_NAME" -- nginx -t 2>&1 || kubectl exec "$POD_NAME" -- openresty -t 2>&1 || print_warn "Cannot test nginx config"
echo ""

# 8. Check logs from inside container (nginx logs)
print_section "8. Nginx Log Files"
print_info "Checking for nginx log files..."
kubectl exec "$POD_NAME" -- sh -c "find /usr/local/openresty -name '*.log' -o -name 'error.log' -o -name 'access.log' 2>/dev/null | head -10" || print_warn "Cannot find log files"
echo ""

# 9. Check environment variables
print_section "9. Environment Variables"
kubectl exec "$POD_NAME" -- env 2>/dev/null | grep -E "PATH|NGINX|OPENRESTY" || print_warn "No relevant environment variables found"
echo ""

# 10. Check container image details
print_section "10. Container Image"
IMAGE=$(kubectl get pod "$POD_NAME" -o jsonpath='{.spec.containers[0].image}')
print_info "Image: $IMAGE"
echo ""

# 11. Check if we can connect to port 8080 from inside
print_section "11. Internal Port Test"
print_info "Testing connection to localhost:8080 from inside container..."
kubectl exec "$POD_NAME" -- sh -c "curl -s http://localhost:8080/ || wget -q -O- http://localhost:8080/ || echo 'Cannot connect to port 8080'" 2>/dev/null || print_warn "Cannot test port from inside"
echo ""

# 12. Check what the container is supposed to do (read deployment spec)
print_section "12. Deployment Specification"
print_info "Checking deployment configuration..."
kubectl get deployment nginx-thrift-deployment -o yaml | grep -A 10 "image:" | head -15
echo ""

print_section "Diagnostic Complete"
print_warn "If nginx is not running, the container may need a command/entrypoint to start it."
print_info "The yg397/openresty-thrift:xenial image may require specific startup commands."

