#!/bin/bash
# Fix the last duplicate - user-service

echo "Fixing user-service duplicate..."
kubectl scale deployment user-service-deployment --replicas=1

echo "Waiting 5 seconds..."
sleep 5

echo "Final pod count:"
kubectl get pods | grep user-service

