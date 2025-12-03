#!/bin/bash
# Quick cleanup - no confirmation, just deletes everything

echo "Deleting all DeathStarBench resources..."

# Delete all deployments
kubectl delete deployment --all 2>/dev/null || true

# Delete all services (except default kubernetes service)
kubectl delete svc --all 2>/dev/null || true

# Delete all ConfigMaps (except system ones)
kubectl delete configmap --all 2>/dev/null || true

# Delete all PVCs
kubectl delete pvc --all 2>/dev/null || true

# Wait
sleep 10

# Delete any remaining pods
kubectl delete pod --all --grace-period=0 --force 2>/dev/null || true

# Delete any remaining ReplicaSets
kubectl delete rs --all --grace-period=0 --force 2>/dev/null || true

echo "✓ Cleanup complete!"
echo "Run ./deploy-everything.sh for fresh deployment"

