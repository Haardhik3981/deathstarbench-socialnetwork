# Fix: Restart Service Deployments

## Issue

The deployment names include `-deployment` suffix, so we need to use the full names.

## Solution

Use this corrected command:

```bash
# Option 1: Use the script (recommended)
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/restart-all-services.sh

# Option 2: Manual restart (one by one)
kubectl rollout restart deployment/compose-post-service-deployment
kubectl rollout restart deployment/user-service-deployment
kubectl rollout restart deployment/social-graph-service-deployment
# ... etc
```

## What This Does

Restarts all service deployments so they pick up the newly created ConfigMap with all files.

## After Restarting

Watch pods restart:

```bash
kubectl get pods -w
```

Then check logs to verify the YAML::BadFile error is gone:

```bash
# Wait a moment for pods to start
sleep 10

# Check logs
kubectl logs -l app=compose-post-service --tail=30
```

If you see the services starting without `YAML::BadFile`, the fix worked!

