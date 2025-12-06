#!/bin/bash

# Quick script to delete all service pods at once
# Faster alternative to restart-pods-with-new-config.sh

set -e

echo "=== Quick Pod Restart ==="
echo ""
echo "This will delete all pods for service deployments."
echo "Kubernetes will automatically recreate them."
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

echo ""
echo "Deleting all service pods..."

# Delete all pods matching service deployment labels
kubectl delete pods -n default \
    -l 'app in (compose-post-service,home-timeline-service,media-service,nginx-thrift,post-storage-service,social-graph-service,text-service,unique-id-service,url-shorten-service,user-mention-service,user-service,user-timeline-service,write-home-timeline-service)' \
    2>/dev/null || echo "Some pods may not exist (this is OK)"

echo ""
echo "✓ Done! Pods are being recreated."
echo ""
echo "Monitor with: kubectl get pods -w"

