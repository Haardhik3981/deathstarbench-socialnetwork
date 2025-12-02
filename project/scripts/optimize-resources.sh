#!/bin/bash

# Script to optimize resource requests instead of scaling

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo ""
print_info "=== Resource Optimization Options ==="
echo ""
print_info "Instead of scaling to 3 nodes, we can optimize:"
echo ""

print_info "Option 1: Reduce Database CPU Requests"
print_warn "  Databases might be requesting too much CPU"
echo "  MongoDB currently: 100m request, 1000m limit"
echo "  Could reduce to: 50m request (still plenty for dev/testing)"
echo ""

print_info "Option 2: Check for Duplicate Pods"
print_warn "  You might have multiple pods from same deployment"
echo "  Check with: kubectl get pods | grep -E 'user-service|mongodb' | wc -l"
echo ""

print_info "Option 3: Reduce Service Replicas"
print_warn "  If you have replicas > 1, reduce to 1 for testing"
echo "  Most deployments should be 1 replica for dev/testing"
echo ""

print_info "Option 4: Reduce nginx-thrift CPU Request"
print_warn "  Temporarily reduce from 100m to 50m"
echo "  Just enough to get it running"
echo ""

echo ""
read -p "Do you want to see current pod counts first? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    print_info "Current pod counts:"
    kubectl get pods | awk '{print $1}' | cut -d'-' -f1-4 | sort | uniq -c | sort -rn | head -20
fi

echo ""
print_info "To reduce nginx-thrift CPU (quick test):"
echo "  kubectl patch deployment nginx-thrift-deployment -p '{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"nginx-thrift\",\"resources\":{\"requests\":{\"cpu\":\"50m\"}}}]}}}}'"

