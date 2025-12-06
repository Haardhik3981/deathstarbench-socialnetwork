# Critical Issue: 100% Request Failure

## What's Happening

### Current Status:
- **100% failure rate** (all requests return 500 errors)
- **0% success rate** (down from ~20% in previous test)
- **All requests fail** at the registration endpoint

### Root Cause:
The `user-service` is **running but not listening on port 9090**. 

**Why?**
1. Service process starts (pgrep finds it)
2. Service tries to initialize MongoDB indexes
3. MongoDB index creation fails with duplicate key errors
4. Service retries indefinitely in a loop
5. Service **never finishes initializing**
6. Service **never starts listening on port 9090**
7. nginx-thrift can't connect → all requests fail with 500 errors

### Evidence:
```
nginx-thrift logs:
"Could not connect to user-service.default.svc.cluster.local:9090 (connection refused)"

user-service logs:
"Error in createIndexes: Index build failed: ... E11000 duplicate key error collection: user.user index: user_id_1 dup key: { user_id: 337 }"
"Failed to create mongodb index, try again" (repeating forever)

Port check:
Port 9090 not found in /proc/net/tcp (service not listening)
```

### Why Readiness Probe Passes:
The readiness probe uses `pgrep -f UserService`, which only checks if the **process is running**, not if the service is **actually ready to accept connections**. The process is running, but stuck in initialization.

---

## Comparison: Before vs Now

### Previous Test (20% success):
- Services were initialized and listening
- Some requests succeeded
- High error rate (56%) but system was functional

### Current Test (0% success):
- Services are running but not initialized
- No requests succeed
- 100% failure rate
- System is completely non-functional

---

## Solutions

### Option 1: Clean MongoDB Database (Recommended)

The MongoDB database has corrupted index state. Clean it up:

```bash
# Delete and recreate user-mongodb pod to reset database
kubectl delete pod -n default -l app=user-mongodb
# Wait for pod to restart
kubectl wait --for=condition=ready pod -n default -l app=user-mongodb --timeout=60s
# Restart user-service to reinitialize
kubectl delete pod -n default -l app=user-service
```

**Pros:**
- Fixes the root cause
- Clean database state
- Services can initialize properly

**Cons:**
- Loses all existing data
- Need to wait for services to reinitialize

---

### Option 2: Fix MongoDB Index Manually

Connect to MongoDB and fix the index:

```bash
# Get MongoDB pod
MONGODB_POD=$(kubectl get pods -n default -l app=user-mongodb -o jsonpath='{.items[0].metadata.name}')

# Connect to MongoDB
kubectl exec -it $MONGODB_POD -n default -- mongosh

# In MongoDB shell:
use user
db.user.dropIndex("user_id_1")
db.user.createIndex({user_id: 1}, {unique: true})

# Then restart user-service
kubectl delete pod -n default -l app=user-service
```

**Pros:**
- Preserves existing data
- Fixes the specific issue

**Cons:**
- More complex
- May have other data issues

---

### Option 3: Fix Readiness Probe (Long-term)

Update readiness probe to check if port is actually listening:

```yaml
readinessProbe:
  exec:
    command: ["/bin/sh", "-c", "timeout 1 bash -c '</dev/tcp/localhost/9090' || exit 1"]
  initialDelaySeconds: 15  # Give more time for initialization
  periodSeconds: 5
  timeoutSeconds: 2
  successThreshold: 1
  failureThreshold: 5  # More failures before marking not ready
```

**Pros:**
- Prevents this issue in the future
- Better readiness detection

**Cons:**
- Doesn't fix current issue
- Need to fix MongoDB first

---

## Recommended Action Plan

1. **Immediate Fix (Option 1):**
   ```bash
   # Clean MongoDB
   kubectl delete pod -n default -l app=user-mongodb
   kubectl wait --for=condition=ready pod -n default -l app=user-mongodb --timeout=60s
   
   # Restart user-service
   kubectl delete pod -n default -l app=user-service
   
   # Wait for service to be ready
   kubectl wait --for=condition=ready pod -n default -l app=user-service --timeout=120s
   ```

2. **Verify Service is Listening:**
   ```bash
   # Check if port 9090 is listening
   kubectl exec -n default $(kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].metadata.name}') -- /bin/sh -c "cat /proc/net/tcp | grep ':2388' && echo 'Port 9090 is listening!' || echo 'Port 9090 NOT listening'"
   ```

3. **Test Connection:**
   ```bash
   # Test from nginx-thrift
   kubectl exec -n default $(kubectl get pods -n default -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}') -- /bin/sh -c "timeout 2 bash -c '</dev/tcp/user-service.default.svc.cluster.local/9090' && echo 'Connection successful!' || echo 'Connection failed'"
   ```

4. **Re-run Test:**
   - Once service is listening, re-run peak test
   - Should see success rate return to previous levels

---

## Why This Happened

The MongoDB database accumulated corrupted state from previous test runs. The duplicate key error suggests:
- Multiple test runs created conflicting data
- Index creation failed partway through
- Service retries indefinitely instead of failing fast

This is a common issue when:
- Running multiple tests without cleaning up
- Database state persists between test runs
- Services don't handle initialization failures gracefully

---

## Prevention

1. **Clean databases between major test runs**
2. **Improve readiness probes** to check actual service readiness (port listening)
3. **Add initialization timeout** so services fail fast instead of retrying forever
4. **Monitor service logs** for initialization errors

