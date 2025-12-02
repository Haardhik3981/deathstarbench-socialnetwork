#!/bin/bash

# Comprehensive diagnostic script for nginx-thrift issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_section "nginx-thrift Diagnostic Script"

# Get pod name
POD_NAME=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    print_error "No nginx-thrift pod found!"
    exit 1
fi

print_info "Found pod: $POD_NAME"
echo ""

# Check pod status
print_section "1. Pod Status"
kubectl get pod "$POD_NAME" -o wide
echo ""

# Check pod events
print_section "2. Pod Events"
kubectl describe pod "$POD_NAME" | grep -A 20 "Events:" || print_warn "No events found"
echo ""

# Check if container is actually running
print_section "3. Container Status"
kubectl get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0]}' | python3 -m json.tool 2>/dev/null || kubectl get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0]}'
echo ""
echo ""

# Check logs (all of them)
print_section "4. Container Logs (all)"
print_info "Getting all logs from container..."
LOGS=$(kubectl logs "$POD_NAME" 2>&1 || echo "No logs available")

if [ -z "$LOGS" ] || [ "$LOGS" = "No logs available" ]; then
    print_warn "No logs found (this is suspicious - nginx should produce logs)"
else
    echo "$LOGS"
fi
echo ""

# Check what's running in the container
print_section "5. Processes Running in Container"
print_info "Checking running processes..."
kubectl exec "$POD_NAME" -- ps aux 2>/dev/null || print_warn "Cannot exec into pod"
echo ""

# Check if nginx is listening on port 8080
print_section "6. Port 8080 Status"
print_info "Checking if anything is listening on port 8080..."
kubectl exec "$POD_NAME" -- netstat -tlnp 2>/dev/null || \
kubectl exec "$POD_NAME" -- ss -tlnp 2>/dev/null || \
kubectl exec "$POD_NAME" -- lsof -i :8080 2>/dev/null || \
print_warn "Cannot check port status (netstat/ss/lsof not available)"
echo ""

# Check nginx configuration
print_section "7. Nginx Configuration"
print_info "Checking if nginx.conf exists and is valid..."
kubectl exec "$POD_NAME" -- cat /etc/nginx/nginx.conf 2>/dev/null | head -50 || print_warn "Cannot read nginx.conf"
echo ""

# Check if nginx process exists
print_section "8. Nginx Process Check"
print_info "Looking for nginx processes..."
kubectl exec "$POD_NAME" -- sh -c "pgrep -a nginx || echo 'No nginx process found'" 2>/dev/null || print_warn "Cannot check for nginx process"
echo ""

# Check mounted volumes
print_section "9. Volume Mounts"
print_info "Checking mounted ConfigMaps..."
kubectl describe pod "$POD_NAME" | grep -A 10 "Mounts:" || print_warn "Cannot check mounts"
echo ""

# Check ConfigMap mounts
print_section "10. ConfigMap Files"
print_info "Checking if ConfigMap files exist in container..."
kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/ 2>/dev/null || print_warn "Cannot list nginx directory"
echo ""

kubectl exec "$POD_NAME" -- ls -la /usr/local/openresty/nginx/lua-scripts/ 2>/dev/null | head -10 || print_warn "Cannot list lua-scripts directory"
echo ""

# Try to manually start nginx and see errors
print_section "11. Manual Nginx Check"
print_info "Checking nginx executable and configuration..."
kubectl exec "$POD_NAME" -- which nginx 2>/dev/null || kubectl exec "$POD_NAME" -- which openresty 2>/dev/null || print_warn "Cannot find nginx/openresty executable"
echo ""

# Check environment variables
print_section "12. Environment Variables"
kubectl exec "$POD_NAME" -- env 2>/dev/null | grep -i nginx || print_warn "No nginx-related environment variables"
echo ""

print_section "Diagnostic Complete"
echo ""
print_info "Summary:"
echo "  Pod: $POD_NAME"
echo "  Status: $(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}')"
echo "  Ready: $(kubectl get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[0].ready}')"
echo ""
print_warn "If nginx is not running, check the configuration and logs above."
