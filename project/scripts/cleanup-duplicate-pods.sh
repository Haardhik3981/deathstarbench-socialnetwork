#!/bin/bash

# Clean up duplicate pods from old deployments

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
print_info "=== Cleaning Up Duplicate/Old Pods ==="
echo ""

# Delete old pending pods that have duplicates running
print_info "Deleting old pending MongoDB pods (keeping running ones)..."
kubectl delete pod user-mongodb-deployment-6475c8b6c9-rkpmc 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod media-mongodb-deployment-57b694888c-7t5dz 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod media-mongodb-deployment-7b8865b889-jtvx4 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod post-storage-mongodb-deployment-7bff569777-lh98h 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod social-graph-mongodb-deployment-69b966959c-qfdtw 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod url-shorten-mongodb-deployment-fc869fc99-wrwcs 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod user-timeline-mongodb-deployment-65c6598bdf-spdrr 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod user-timeline-mongodb-deployment-69c6c64fb7-clqcc 2>/dev/null || print_warn "Pod already deleted"

print_info "Deleting old pending Redis pods..."
kubectl delete pod home-timeline-redis-deployment-f765dd49c-zkm8k 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod social-graph-redis-deployment-78cf467b6d-jhxwb 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod url-shorten-memcached-deployment-688c745bd-jxssb 2>/dev/null || print_warn "Pod already deleted"
kubectl delete pod media-memcached-deployment-8677f499c-468zc 2>/dev/null || print_warn "Pod already deleted"

print_info "Deleting old nginx-thrift pod (keeping new one)..."
kubectl delete pod nginx-thrift-deployment-7664fdf74f-n7xg9 2>/dev/null || print_warn "Pod already deleted"

print_info "Deleting stuck nginx-deployment..."
kubectl delete pod nginx-deployment-74c549fc55-sjmm7 2>/dev/null || print_warn "Pod already deleted"

print_info ""
print_info "Cleanup complete!"
print_info "Check status: kubectl get pods"

