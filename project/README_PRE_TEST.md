# Pre-Test Checklist - Running k6 Tests

Before running k6 load tests, ensure your deployment is ready and all components are working correctly.

## Quick Start

Run the pre-test checklist script:

```bash
cd /path/to/deathstarbench-socialnetwork/project
./scripts/pre-test-checklist.sh
```

This script will:
1. ✅ Verify all deployments are ready
2. ✅ Check nginx-thrift accessibility
3. ✅ Test the endpoint
4. ✅ Verify k6 is installed
5. ✅ Check test files exist

## Manual Verification

If you prefer to verify manually:

### Step 1: Verify Deployment

```bash
./scripts/verify-deployment.sh
```

This checks:
- ✅ All ConfigMaps exist (including nginx-lua-scripts)
- ✅ All MongoDB deployments are ready (6 instances)
- ✅ All Redis deployments are ready (4 instances, including compose-post-redis)
- ✅ All Memcached deployments are ready (4 instances)
- ✅ All microservice deployments are ready (11 services)
- ✅ write-home-timeline services are ready (optional)
- ✅ nginx-thrift gateway is ready
- ✅ nginx-thrift service exists
- ✅ Jaeger is ready (optional)

### Step 2: Check Pod Status

```bash
kubectl get pods
```

You should see:
- All pods in "Running" status
- No pods in "CrashLoopBackOff" or "Error" status
- Expected pod count: ~28-30 pods

### Step 3: Check nginx-thrift Service

```bash
kubectl get svc nginx-thrift
```

The service should exist and be accessible.

### Step 4: Start Port-Forward

```bash
# In a separate terminal
kubectl port-forward svc/nginx-thrift 8080:8080
```

Keep this running while you run k6 tests.

### Step 5: Test Endpoint

```bash
curl http://localhost:8080/
```

Should return a response (200, 404, or 302 is fine - just means it's responding).

## What the Deploy Script Does

The `deploy-everything.sh` script includes all our improvements:

1. ✅ **Creates ConfigMaps**:
   - `deathstarbench-config` (nginx.conf, service-config.json, etc.)
   - `nginx-pages` (HTML/JS/CSS)
   - `nginx-gen-lua` (generated Lua files)
   - `nginx-lua-scripts` (using `create-lua-configmap-solution.sh`)

2. ✅ **Deploys Databases**:
   - 6 MongoDB instances
   - 4 Redis instances (including `compose-post-redis`)
   - 4 Memcached instances

3. ✅ **Deploys Microservices**:
   - 11 core microservices
   - write-home-timeline-service (optional)
   - write-home-timeline-rabbitmq (optional)

4. ✅ **Deploys Gateway**:
   - nginx-thrift with all fixes (fqdn_suffix, resolver, Lua scripts)

5. ✅ **Creates Services**:
   - All Kubernetes Service objects for networking

## Expected Pod Count

After deployment, you should have approximately:
- 6 MongoDB pods
- 4 Redis pods (including compose-post-redis)
- 4 Memcached pods
- 11 microservice pods
- 1 nginx-thrift pod
- 1 Jaeger pod
- 1-2 write-home-timeline pods (optional)

**Total: ~28-30 pods**

## Troubleshooting

### Pods Not Ready

```bash
# Check pod status
kubectl get pods

# Check pod logs
kubectl logs <pod-name>

# Check pod events
kubectl describe pod <pod-name>
```

### nginx-thrift Not Working

```bash
# Check nginx-thrift logs
kubectl logs -l app=nginx-thrift --tail=100

# Check if ConfigMaps are mounted
kubectl describe pod -l app=nginx-thrift | grep -A 10 "Mounts:"
```

### ConfigMaps Missing

```bash
# Check ConfigMaps
kubectl get configmap

# Recreate if needed
./scripts/create-lua-configmap-solution.sh
```

### Port-Forward Issues

```bash
# Check if port 8080 is already in use
lsof -i :8080

# Kill existing port-forward
pkill -f "kubectl port-forward"

# Start fresh
kubectl port-forward svc/nginx-thrift 8080:8080
```

## Running Tests

Once verification passes:

```bash
# Terminal 1: Keep port-forward running
kubectl port-forward svc/nginx-thrift 8080:8080

# Terminal 2: Run k6 test
cd /path/to/deathstarbench-socialnetwork/project
k6 run k6-tests/constant-load.js
```

Or with explicit BASE_URL:

```bash
BASE_URL=http://localhost:8080 k6 run k6-tests/constant-load.js
```

## Key Improvements Included

All these improvements are included in `deploy-everything.sh`:

1. ✅ **compose-post-redis** - Added to fix compose-post errors
2. ✅ **write-home-timeline services** - Added for async processing
3. ✅ **Lua scripts ConfigMaps** - Properly created with subdirectories
4. ✅ **nginx-thrift configuration** - Includes fqdn_suffix and correct resolver
5. ✅ **All services** - All Kubernetes Service objects created

## Next Steps

After verification:
1. Run `./scripts/pre-test-checklist.sh` to confirm everything is ready
2. Start port-forward in a separate terminal
3. Run k6 tests
4. Monitor results and check for any errors

The tests are now configured to avoid the "ZADD: no key specified" error by ensuring users have followers before composing posts.

