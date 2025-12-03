# Fixing 500 Internal Server Errors

## Problem Summary

Your k6 tests are failing with **500 Internal Server Error** because the nginx-thrift pod cannot find the Lua scripts it needs to handle API requests.

### Root Cause

The error in the logs shows:
```
module 'wrk2-api/user/register' not found:
no file '/usr/local/openresty/nginx/lua-scripts/wrk2-api/user/register.lua'
```

This means the `nginx-lua-scripts` ConfigMap either:
1. Doesn't exist
2. Exists but doesn't contain the required files
3. Was created incorrectly (files not preserving directory structure)

## Solution

You need to create the `nginx-lua-scripts` ConfigMap with all the Lua scripts from the DeathStarBench source code.

### Step 1: Verify the Lua Scripts Source Directory Exists

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork
ls -la socialNetwork/nginx-web-server/lua-scripts/wrk2-api/user/register.lua
```

This file should exist. If it doesn't, you need to check out the DeathStarBench repository.

### Step 2: Create the ConfigMap

Run the script that creates the ConfigMap with all Lua files:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/create-lua-configmap-direct.sh
```

This script:
- Deletes any existing `nginx-lua-scripts` ConfigMap
- Creates a new ConfigMap with all required Lua files
- Preserves the directory structure (e.g., `wrk2-api/user/register.lua`)
- Restarts the nginx-thrift deployment

### Step 3: Verify the ConfigMap Was Created

```bash
kubectl get configmap nginx-lua-scripts -o yaml | grep -A 5 "wrk2-api/user/register.lua"
```

You should see the file content. If you see nothing, the ConfigMap wasn't created correctly.

### Step 4: Restart the nginx-thrift Pod

Even if the script restarts it, manually restart to ensure it picks up the new ConfigMap:

```bash
kubectl rollout restart deployment/nginx-thrift-deployment
kubectl rollout status deployment/nginx-thrift-deployment
```

### Step 5: Verify the Files Are in the Pod

Once the pod is running, check if the files are actually mounted:

```bash
# Get the pod name
POD_NAME=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}')

# Check if the file exists
kubectl exec $POD_NAME -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/user/register.lua
```

If this command succeeds, the file is mounted correctly!

### Step 6: Test the Endpoint Again

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./k6-tests/test-endpoint.sh
```

You should now see `Response Status: 200` instead of `500`.

## Alternative: Manual ConfigMap Creation

If the script doesn't work, create the ConfigMap manually:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/socialNetwork/nginx-web-server/lua-scripts

# Delete old ConfigMap
kubectl delete configmap nginx-lua-scripts 2>/dev/null || true

# Create new ConfigMap with all files
kubectl create configmap nginx-lua-scripts \
  --from-file=api/home-timeline/read.lua=api/home-timeline/read.lua \
  --from-file=api/post/compose.lua=api/post/compose.lua \
  --from-file=api/user/follow.lua=api/user/follow.lua \
  --from-file=api/user/get_followee.lua=api/user/get_followee.lua \
  --from-file=api/user/get_follower.lua=api/user/get_follower.lua \
  --from-file=api/user/login.lua=api/user/login.lua \
  --from-file=api/user/register.lua=api/user/register.lua \
  --from-file=api/user/unfollow.lua=api/user/unfollow.lua \
  --from-file=api/user-timeline/read.lua=api/user-timeline/read.lua \
  --from-file=wrk2-api/home-timeline/read.lua=wrk2-api/home-timeline/read.lua \
  --from-file=wrk2-api/post/compose.lua=wrk2-api/post/compose.lua \
  --from-file=wrk2-api/user/follow.lua=wrk2-api/user/follow.lua \
  --from-file=wrk2-api/user/register.lua=wrk2-api/user/register.lua \
  --from-file=wrk2-api/user/unfollow.lua=wrk2-api/user/unfollow.lua \
  --from-file=wrk2-api/user-timeline/read.lua=wrk2-api/user-timeline/read.lua

# Restart the deployment
kubectl rollout restart deployment/nginx-thrift-deployment
```

## Understanding the Issue

### How ConfigMaps Work with Directories

When you mount a ConfigMap as a directory:
- Each key in the ConfigMap becomes a file
- Keys with slashes (like `wrk2-api/user/register.lua`) create the directory structure
- The file is created at the mount path + the key path

So if you mount the ConfigMap at `/usr/local/openresty/nginx/lua-scripts`:
- Key `wrk2-api/user/register.lua` → File at `/usr/local/openresty/nginx/lua-scripts/wrk2-api/user/register.lua` ✅

### Why It Was Failing

The Lua `require` function looks for files in specific paths. When nginx tries to:
```lua
local client = require "wrk2-api/user/register"
```

It searches for `/usr/local/openresty/nginx/lua-scripts/wrk2-api/user/register.lua`.

If the ConfigMap doesn't have this file, the require fails and nginx returns a 500 error.

## Additional Notes

### Other Required ConfigMaps

The nginx-thrift deployment also needs:
- `nginx-gen-lua` - Generated Lua files from Thrift definitions
- `nginx-pages` - HTML pages and static assets
- `deathstarbench-config` - Service configuration and Jaeger config

Make sure all of these are created. Check with:
```bash
kubectl get configmap | grep nginx
```

### Checking Pod Logs

After fixing, check the logs to confirm there are no more errors:
```bash
kubectl logs -l app=nginx-thrift --tail=20
```

You should see normal nginx logs, not Lua module errors.

## After Fixing

Once the ConfigMap is created and the pod restarted:
1. ✅ The endpoint should return 200 OK
2. ✅ Your k6 tests should pass
3. ✅ CPU usage will increase (requests are being processed)
4. ✅ No more "module not found" errors in logs

Run your k6 test again:
```bash
BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh constant-load
```

You should now see successful requests! 🎉

