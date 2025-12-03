# Changes Applied to DeathStarBench Deployment

This document lists all changes made during the debugging and fix session to get the DeathStarBench social network running on GKE.

## Critical Source Code Fix

### 1. Fixed `SocialGraphHandler.h` Bug
**File**: `socialNetwork/src/SocialGraphService/SocialGraphHandler.h`

**Problem**: When a user has no followers, the code was calling Redis `ZADD` with an empty `redis_zset`, causing "ZADD: no key specified" errors.

**Fix Applied**:
- Added check `if (!redis_zset.empty())` before calling `zadd()` in both `GetFollowers()` and `GetFollowees()` methods
- This prevents the error when users have no followers/followees

**Lines Changed**:
- Line ~595: Added empty check before Redis update in `GetFollowers()`
- Line ~750: Added empty check before Redis update in `GetFollowees()`

**⚠️ IMPORTANT**: You MUST rebuild the Docker image with this fix:
```bash
# 1. Build the C++ code (if you have a build process)
# 2. Rebuild Docker image
docker build -t <your-registry>/social-network-microservices:latest .
# 3. Push to registry
docker push <your-registry>/social-network-microservices:latest
# 4. Restart social-graph-service
kubectl rollout restart deployment/social-graph-service-deployment
```

## Infrastructure Changes

### 2. Added `compose-post-redis` Deployment
**Files**:
- `kubernetes/deployments/databases/redis-deployments.yaml` - Added compose-post-redis deployment
- `kubernetes/services/all-databases.yaml` - Added compose-post-redis service

**Why**: The `compose-post-service` requires `compose-post-redis` but it was missing from the deployment.

**Status**: ✅ Deployed and running

### 3. Added `write-home-timeline-service` and RabbitMQ
**Files Created**:
- `kubernetes/deployments/write-home-timeline-service-deployment.yaml`
- `kubernetes/deployments/write-home-timeline-rabbitmq-deployment.yaml`
- `kubernetes/services/write-home-timeline-rabbitmq-service.yaml`

**Why**: These services provide async processing for home timeline updates via RabbitMQ. While `home-timeline-service` can work without them (it updates Redis directly), they provide better scalability.

**Status**: ✅ Deployed (optional but recommended)

### 4. Updated `deploy-everything.sh`
**Changes**:
- Updated Redis deployment count comment (now 4 instances, not 3)
- Added deployment of `write-home-timeline-service` and RabbitMQ
- Updated Lua scripts ConfigMap creation to use `create-lua-configmap-solution.sh`
- Added warnings about rebuilding Docker image if source code was modified
- Added summary section at end listing all changes

**Status**: ✅ Script updated and ready to use

## Configuration Changes (Already Applied)

### 5. nginx-thrift Configuration
**Files Modified** (from previous sessions):
- `kubernetes/deployments/nginx-thrift-deployment.yaml` - Added `fqdn_suffix` environment variable
- `kubernetes/configmaps/deathstarbench-config.yaml` - Updated `nginx.conf` with correct resolver and `env fqdn_suffix;`
- `socialNetwork/nginx-web-server/conf/nginx.conf` - Added `env fqdn_suffix;` directive

**Status**: ✅ Already applied and working

### 6. Lua Scripts ConfigMaps
**Files Created**:
- `scripts/create-lua-configmap-solution.sh` - Creates separate ConfigMaps for each Lua script subdirectory

**Status**: ✅ Working solution in place

## Testing Changes

### 7. Updated k6 Test Script
**File**: `k6-tests/constant-load.js`

**Changes**:
- Fixed teardown function to handle undefined metrics gracefully
- Added better error logging

**Status**: ✅ Updated

## Deployment Checklist

Before running `deploy-everything.sh`, ensure:

1. ✅ **Source code fix applied**: `SocialGraphHandler.h` has the empty check
2. ✅ **Docker image rebuilt**: If you modified source code, rebuild and push the image
3. ✅ **All YAML files in place**: 
   - `redis-deployments.yaml` includes compose-post-redis
   - `write-home-timeline-*.yaml` files exist
   - `all-databases.yaml` includes compose-post-redis service
4. ✅ **Scripts updated**: `deploy-everything.sh` includes all new deployments

## What to Do Next

1. **Rebuild Docker Image** (if source code was modified):
   ```bash
   # Navigate to DeathStarBench source
   cd ../socialNetwork
   
   # Build (adjust for your build process)
   # Then build Docker image
   docker build -t <your-registry>/social-network-microservices:latest .
   docker push <your-registry>/social-network-microservices:latest
   ```

2. **Run Deployment**:
   ```bash
   cd project
   ./deploy-everything.sh
   ```

3. **Verify Everything is Running**:
   ```bash
   kubectl get pods
   # Should see:
   # - 4 Redis pods (including compose-post-redis)
   # - write-home-timeline-service pod
   # - write-home-timeline-rabbitmq pod
   # - All other services
   ```

4. **Test**:
   ```bash
   kubectl port-forward svc/nginx-thrift 8080:8080
   k6 run k6-tests/constant-load.js
   ```

## Files Modified Summary

### Source Code
- `socialNetwork/src/SocialGraphService/SocialGraphHandler.h` - **CRITICAL FIX**

### Kubernetes Deployments
- `kubernetes/deployments/databases/redis-deployments.yaml` - Added compose-post-redis
- `kubernetes/deployments/write-home-timeline-service-deployment.yaml` - **NEW**
- `kubernetes/deployments/write-home-timeline-rabbitmq-deployment.yaml` - **NEW**

### Kubernetes Services
- `kubernetes/services/all-databases.yaml` - Added compose-post-redis service
- `kubernetes/services/write-home-timeline-rabbitmq-service.yaml` - **NEW**

### Scripts
- `deploy-everything.sh` - Updated to include all new deployments
- `scripts/create-lua-configmap-solution.sh` - Already exists (from previous session)
- `scripts/deploy-compose-post-redis.sh` - **NEW** (helper script)
- `scripts/deploy-missing-services.sh` - **NEW** (helper script)
- `scripts/check-social-graph-redis.sh` - **NEW** (diagnostic script)
- `scripts/diagnose-compose-post-error.sh` - **NEW** (diagnostic script)
- `scripts/deep-dive-zadd-error.sh` - **NEW** (diagnostic script)
- `scripts/fix-compose-post-errors.sh` - **NEW** (diagnostic script)
- `scripts/restart-services-for-compose-fix.sh` - **NEW** (helper script)

### Test Scripts
- `k6-tests/constant-load.js` - Fixed teardown function

## Notes

- All changes are **permanent** and will be reflected when you rebuild
- The source code fix is the **most critical** - without it, compose-post will fail for users with no followers
- The `write-home-timeline-service` is optional but recommended for better performance
- The `compose-post-redis` is **required** - without it, compose-post will fail

## Verification

After deployment, verify:
```bash
# Check all Redis pods
kubectl get pods -l app=compose-post-redis
kubectl get pods -l app=home-timeline-redis
kubectl get pods -l app=social-graph-redis
kubectl get pods -l app=user-timeline-redis

# Check write-home-timeline services
kubectl get pods -l app=write-home-timeline-service
kubectl get pods -l app=write-home-timeline-rabbitmq

# Check services
kubectl get svc compose-post-redis
kubectl get svc write-home-timeline-rabbitmq

# Test compose-post endpoint (should not have ZADD errors)
kubectl port-forward svc/nginx-thrift 8080:8080
# Then run k6 test
```

