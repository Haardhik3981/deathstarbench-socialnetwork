#!/bin/bash

# Deploy missing write-home-timeline services

set -e

echo "=== Deploying Missing Services ==="
echo ""

# Deploy RabbitMQ
echo "Step 1: Deploying write-home-timeline-rabbitmq..."
kubectl apply -f kubernetes/deployments/write-home-timeline-rabbitmq-deployment.yaml
kubectl apply -f kubernetes/services/write-home-timeline-rabbitmq-service.yaml
echo "✓ RabbitMQ deployed"
echo ""

# Wait for RabbitMQ to be ready
echo "Step 2: Waiting for RabbitMQ..."
sleep 10
kubectl wait --for=condition=ready pod -l app=write-home-timeline-rabbitmq --timeout=120s || echo "⚠ RabbitMQ not ready yet"
echo ""

# Deploy write-home-timeline-service
echo "Step 3: Deploying write-home-timeline-service..."
kubectl apply -f kubernetes/deployments/write-home-timeline-service-deployment.yaml
echo "✓ Service deployed"
echo ""

# Wait for service to be ready
echo "Step 4: Waiting for write-home-timeline-service..."
sleep 10
kubectl wait --for=condition=ready pod -l app=write-home-timeline-service --timeout=120s || echo "⚠ Service not ready yet"
echo ""

# Verify
echo "Step 5: Verifying deployments..."
kubectl get pods -l app=write-home-timeline-rabbitmq
kubectl get pods -l app=write-home-timeline-service
kubectl get svc write-home-timeline-rabbitmq
echo ""

echo "=== Done ==="
echo ""
echo "Note: home-timeline-service can work without these (it updates Redis directly),"
echo "but these services provide async processing via RabbitMQ."

