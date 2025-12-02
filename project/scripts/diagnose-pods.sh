#!/bin/bash

# Diagnostic script to check pod issues

echo "=== Checking PVC Status ==="
kubectl get pvc

echo -e "\n=== Checking Storage Classes ==="
kubectl get storageclass

echo -e "\n=== Checking Node Resources ==="
kubectl describe nodes | grep -A 10 "Allocated resources" | head -20

echo -e "\n=== Checking New Pod Status ==="
kubectl get pods | grep -E "Pending|Error|CrashLoopBackOff" | head -20

echo -e "\n=== Sample Pod Event (checking a pending pod) ==="
PENDING_POD=$(kubectl get pods | grep Pending | head -1 | awk '{print $1}')
if [ -n "$PENDING_POD" ]; then
    echo "Checking: $PENDING_POD"
    kubectl describe pod "$PENDING_POD" | tail -30
else
    echo "No pending pods found"
fi

echo -e "\n=== Checking New Service Pod Logs (if running) ==="
NEW_USER_POD=$(kubectl get pods | grep user-service-deployment | grep -v CrashLoopBackOff | grep -v Error | head -1 | awk '{print $1}')
if [ -n "$NEW_USER_POD" ]; then
    echo "Checking logs for: $NEW_USER_POD"
    kubectl logs "$NEW_USER_POD" --tail=50
else
    echo "No new user-service pod found. Checking latest crash loop pod:"
    CRASH_POD=$(kubectl get pods | grep user-service-deployment | grep CrashLoopBackOff | head -1 | awk '{print $1}')
    if [ -n "$CRASH_POD" ]; then
        kubectl logs "$CRASH_POD" --tail=50
    fi
fi

