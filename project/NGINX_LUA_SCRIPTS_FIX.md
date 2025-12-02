# Fix for nginx-lua-scripts ConfigMap Issue

## Problem

The `nginx-thrift` gateway isn't starting properly because the `nginx-lua-scripts` ConfigMap is either missing or empty. This causes nginx-thrift to fail to start, resulting in "connection refused" errors when trying to port-forward.

## Root Cause

1. The `nginx-thrift-deployment.yaml` expects the `nginx-lua-scripts` ConfigMap to be mounted
2. The ConfigMap needs to contain all Lua script files from `nginx-web-server/lua-scripts/`
3. The directory has subdirectories (`api/`, `wrk2-api/`, etc.) that need to be preserved
4. Standard `kubectl create configmap --from-file=<dir>` doesn't always preserve subdirectory structure correctly

## Solution

A fix script (`scripts/fix-nginx-lua-scripts.sh`) has been created that:
1. Finds all Lua script files (including in subdirectories)
2. Creates the ConfigMap with all files, preserving directory structure
3. Verifies the ConfigMap was created correctly

## How to Fix

### Option 1: Use the Fix Script (Recommended)

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# Run the fix script
./scripts/fix-nginx-lua-scripts.sh

# Restart nginx-thrift to pick up the new ConfigMap
kubectl rollout restart deployment/nginx-thrift-deployment

# Wait for it to restart and check status
kubectl get pods -l app=nginx-thrift

# Check logs to verify it's working
kubectl logs -l app=nginx-thrift --tail=50
```

### Option 2: The Fix is Now Integrated into deploy-everything.sh

The `deploy-everything.sh` script now automatically creates the `nginx-lua-scripts` ConfigMap when deploying. However, if you already have a deployment running, you may need to:

1. Run the fix script manually:
   ```bash
   ./scripts/fix-nginx-lua-scripts.sh
   ```

2. Restart nginx-thrift:
   ```bash
   kubectl rollout restart deployment/nginx-thrift-deployment
   ```

## Verification

After fixing, verify nginx-thrift is working:

```bash
# Check pod is running
kubectl get pods -l app=nginx-thrift

# Check it's listening on port 8080
kubectl logs -l app=nginx-thrift | grep -i "listening\|started\|error"

# Try port-forwarding
kubectl port-forward svc/nginx-thrift-service 8080:8080

# In another terminal, test it:
curl http://localhost:8080/
```

## Expected Behavior After Fix

1. ✅ `nginx-lua-scripts` ConfigMap exists with multiple files
2. ✅ nginx-thrift pod starts successfully (status: Running)
3. ✅ nginx-thrift listens on port 8080
4. ✅ Port-forwarding works without "connection refused" errors
5. ✅ You can access the API gateway

## Troubleshooting

If the fix script doesn't work:

1. **Check DeathStarBench source exists:**
   ```bash
   ls -la ../socialNetwork/nginx-web-server/lua-scripts/
   ```

2. **Manually verify ConfigMap:**
   ```bash
   kubectl get configmap nginx-lua-scripts -o yaml
   kubectl describe configmap nginx-lua-scripts
   ```

3. **Check nginx-thrift logs:**
   ```bash
   kubectl logs -l app=nginx-thrift --tail=100
   ```

4. **Check nginx-thrift pod events:**
   ```bash
   kubectl describe pod -l app=nginx-thrift
   ```

