# Fix nginx-thrift Gateway

## Problem Found

The `nginx-lua-scripts` ConfigMap shows **0 data files**! This means nginx can't find the Lua scripts it needs to handle API requests.

## Solution

### Step 1: Recreate nginx-lua-scripts ConfigMap

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/fix-nginx-lua-scripts-configmap.sh
```

This will:
- Check the lua-scripts directory
- Delete the empty ConfigMap
- Recreate it with all Lua files from DeathStarBench source

### Step 2: Restart nginx-thrift

```bash
kubectl rollout restart deployment/nginx-thrift-deployment
```

### Step 3: Wait and Check Logs

```bash
# Wait for pod to restart (30-60 seconds)
sleep 30

# Check if it's running
kubectl get pods -l app=nginx-thrift

# Check logs
kubectl logs -l app=nginx-thrift --tail=50
```

## What to Look For

**Good signs:**
- Pod status: `Running` (not CrashLoopBackOff)
- Logs show nginx starting successfully
- No errors about missing Lua files

**Bad signs:**
- Still crashing
- Errors about missing files
- Cannot find module errors

## After Fixing

Once nginx-thrift is running, test the API:

```bash
# Get LoadBalancer IP
NGINX_IP=$(kubectl get service nginx-thrift-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test endpoint
curl http://${NGINX_IP}:8080/wrk2-api/user/register -X POST \
  -d "user_id=1&username=testuser&first_name=Test&last_name=User&password=testpass"
```

## Expected Result

After fixing the ConfigMap and restarting:
- nginx-thrift pod should start successfully
- No more crashes
- API endpoints should be accessible
- Gateway can route requests to services

