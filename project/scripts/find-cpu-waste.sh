#!/bin/bash

# Find where CPU is actually being wasted

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
print_section "Finding CPU Waste"

echo ""
print_section "1. Count Pods by Type (Looking for Duplicates)"
echo "Services:"
kubectl get pods | grep -E "service-deployment" | wc -l
echo "Expected: 11 services"
echo ""

echo "MongoDB:"
kubectl get pods | grep mongodb | wc -l
echo "Expected: 6 MongoDB"
echo ""

echo "Redis:"
kubectl get pods | grep redis | wc -l
echo "Expected: 3 Redis"
echo ""

echo "Memcached:"
kubectl get pods | grep memcached | wc -l
echo "Expected: 4 Memcached"
echo ""

print_section "2. Pods by Deployment (Duplicates?)"
kubectl get pods | awk '{print $1}' | cut -d'-' -f1-4 | sort | uniq -c | sort -rn | head -20

echo ""
print_section "3. Check for Multiple Pods from Same Deployment"
echo "These should all be 1 (one pod per deployment):"
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.ownerReferences[0].name}{"\n"}{end}' 2>/dev/null | \
  sort | uniq -c | sort -rn | head -20 || \
  print_warn "Could not check (jq might not be installed)"

echo ""
print_section "4. Actual Resource Requests Breakdown"
echo "Let's calculate what SHOULD be requested:"
echo ""
echo "11 Services × 100m =  1100m"
echo "6  MongoDB  × 100m =   600m"
echo "3  Redis    ×  50m =   150m"
echo "4  Memcached ×  50m =  200m"
echo "Jaeger            =   100m"
echo "nginx-thrift      =   100m"
echo "----------------------------"
echo "Total Expected:   ~  2250m"
echo ""
print_warn "But you're requesting 5685m - that's 3400m extra!"

echo ""
print_section "5. Quick Optimization - Reduce nginx-thrift CPU"
print_info "Try reducing nginx-thrift from 100m to 50m:"
echo ""
echo "kubectl patch deployment nginx-thrift-deployment -p '{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"nginx-thrift\",\"resources\":{\"requests\":{\"cpu\":\"50m\"}}}]}}}}'"
echo ""
print_info "This alone might free up enough CPU for it to schedule on current nodes!"

