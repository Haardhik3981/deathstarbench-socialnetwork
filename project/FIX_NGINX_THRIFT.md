# Fix nginx-thrift CrashLoopBackOff

## Problem Found

From the diagnostic output:

1. **nginx-lua-scripts ConfigMap is EMPTY** (0 DATA)
   - This is the root cause!
   - nginx-thrift needs Lua scripts to handle requests
   - Without them, nginx exits immediately

2. **Container exits normally** (Exit Code: 0)
   - Not crashing, just exiting because it can't find required files
   - Health checks fail because nginx isn't running

3. **Container runs for ~90 seconds then exits**
   - This suggests nginx starts but exits when it can't find Lua scripts

## Solution

### Option 1: Use the existing fix script

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/fix-nginx-lua-scripts-configmap.sh
```

This script will:
1. Find the DeathStarBench source directory
2. Delete the empty ConfigMap
3. Recreate it with all Lua script files
4. Restart nginx-thrift

### Option 2: Manual fix

If the script doesn't work, recreate the ConfigMap manually:

```bash
# Find your DeathStarBench source (adjust path as needed)
DSB_ROOT="/path/to/DeathStarBench/socialNetwork"

# Delete empty ConfigMap
kubectl delete configmap nginx-lua-scripts

# Recreate with Lua scripts
kubectl create configmap nginx-lua-scripts \
  --from-file="${DSB_ROOT}/nginx-web-server/lua-scripts/"

# Verify it has files now
kubectl get configmap nginx-lua-scripts

# Restart nginx-thrift
kubectl rollout restart deployment/nginx-thrift-deployment
```

## After Fixing

Once the ConfigMap is recreated with files:

1. The pod will restart automatically
2. nginx-thrift should start successfully
3. Health checks should pass
4. Pod should become Ready (1/1)

## Verify

```bash
# Check ConfigMap has files
kubectl get configmap nginx-lua-scripts

# Check pod status
kubectl get pods -l app=nginx-thrift

# Watch it start
kubectl get pods -l app=nginx-thrift -w
```

