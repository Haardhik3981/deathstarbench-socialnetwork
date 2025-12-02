# Debugging Config Mount Issue

## Problem

Services still getting `YAML::BadFile` error even though we fixed the volume mounts.

## Possible Causes

1. **ConfigMap doesn't have the files** - Files weren't created correctly
2. **Files are empty/corrupted** - ConfigMap has files but they're not valid
3. **Path mismatch** - Services looking in wrong place
4. **Deployment not updated** - Old deployment still running

## Debug Steps

### Step 1: Verify ConfigMap Has Files

```bash
# Check if ConfigMap exists and has files
kubectl get configmap deathstarbench-config

# Check if jaeger-config.yml is in ConfigMap
kubectl get configmap deathstarbench-config -o jsonpath='{.data.jaeger-config\.yml}' | head -10

# Check if service-config.json is in ConfigMap  
kubectl get configmap deathstarbench-config -o jsonpath='{.data.service-config\.json}' | head -10
```

### Step 2: Check Deployment is Using Correct Mounts

```bash
# Verify deployment has subPath mounts
kubectl get deployment compose-post-service-deployment -o yaml | grep -A 10 "volumeMounts:"
```

### Step 3: Check Files in Pod (if pod starts)

```bash
# Get a pod name
POD=$(kubectl get pods | grep compose-post-service | head -1 | awk '{print $1}')

# Try to check files (if pod is running)
kubectl exec $POD -- ls -la /social-network-microservices/config/ 2>&1
kubectl exec $POD -- cat /social-network-microservices/config/jaeger-config.yml 2>&1
```

## Quick Diagnostic

Run this script:

```bash
./scripts/debug-config-mount.sh
```

