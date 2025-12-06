#!/bin/bash

# Cleanup Pending Pods That Can't Be Scheduled
# Use this when pods are stuck in Pending state due to resource constraints

set +e

NAMESPACE="${NAMESPACE:-default}"

echo "=== CLEANING UP PENDING PODS ==="
echo ""

# Find all pending pods
PENDING_PODS=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Pending --no-headers 2>/dev/null | awk '{print $1}')

if [ -z "$PENDING_PODS" ]; then
    echo "✓ No pending pods found"
    exit 0
fi

echo "Found pending pods:"
echo "$PENDING_PODS" | while read -r pod; do
    if [ -n "$pod" ]; then
        echo "  - $pod"
    fi
done
echo ""

# Check why they're pending
echo "Checking why pods are pending..."
echo "$PENDING_PODS" | while read -r pod; do
    if [ -n "$pod" ]; then
        REASON=$(kubectl describe pod "$pod" -n "$NAMESPACE" 2>/dev/null | grep "FailedScheduling" | tail -1 | awk -F: '{print $2}' | xargs)
        if [ -n "$REASON" ]; then
            echo "  $pod: $REASON"
        fi
    fi
done
echo ""

# Ask for confirmation
read -p "Delete these pending pods? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Delete pending pods
echo ""
echo "Deleting pending pods..."
echo "$PENDING_PODS" | while read -r pod; do
    if [ -n "$pod" ]; then
        echo "  Deleting $pod..."
        kubectl delete pod "$pod" -n "$NAMESPACE" 2>/dev/null
    fi
done

echo ""
echo "✓ Cleanup complete"
echo ""
echo "Note: If HPAs are active, they may try to recreate these pods."
echo "To prevent this, you may need to:"
echo "  1. Enable cluster autoscaling to add more nodes"
echo "  2. Reduce resource requests for some pods"
echo "  3. Temporarily reduce HPA minReplicas"

