#!/bin/bash

# Restart services to fix compose-post errors

set -e

echo "=== Restarting Services to Fix Compose Post Errors ==="
echo ""

echo "Step 1: Restarting home-timeline-service..."
kubectl rollout restart deployment/home-timeline-service-deployment
echo "✓ Restarted"
echo ""

echo "Step 2: Restarting compose-post-service..."
kubectl rollout restart deployment/compose-post-service-deployment
echo "✓ Restarted"
echo ""

echo "Step 3: Waiting for pods to be ready..."
echo "Waiting for home-timeline-service..."
kubectl wait --for=condition=ready pod -l app=home-timeline-service --timeout=120s || echo "⚠ Not ready yet"
echo ""

echo "Waiting for compose-post-service..."
kubectl wait --for=condition=ready pod -l app=compose-post-service --timeout=120s || echo "⚠ Not ready yet"
echo ""

echo "Step 4: Verifying pods are running..."
kubectl get pods -l app=home-timeline-service
kubectl get pods -l app=compose-post-service
echo ""

echo "=== Done ==="
echo ""
echo "Services have been restarted. Wait a few seconds for them to fully initialize,"
echo "then run your k6 test again:"
echo "  k6 run k6-tests/constant-load.js"

