# Quick Verification Commands

Use these commands to verify your system is ready for testing.

## Option 1: Run the Verification Script (Recommended)

```bash
./scripts/verify-system-ready.sh
```

This comprehensive script checks:
- ✅ All service pods are running and ready
- ✅ Service endpoints are configured
- ✅ Databases are ready
- ✅ Services are listening on ports
- ✅ Service-to-service connectivity
- ✅ HTTP endpoint accessibility
- ✅ No initialization errors

---

## Option 2: Manual Commands

### 1. Check All Service Pods Status

```bash
kubectl get pods -n default -l 'app in (compose-post-service,home-timeline-service,media-service,nginx-thrift,post-storage-service,social-graph-service,text-service,unique-id-service,url-shorten-service,user-mention-service,user-service,user-timeline-service)'
```

**Expected:** All pods show `Running` and `1/1` (or `2/2` for nginx-thrift)

---

### 2. Check Critical Services

```bash
# Check user-service
kubectl get pods -n default -l app=user-service

# Check unique-id-service
kubectl get pods -n default -l app=unique-id-service

# Check nginx-thrift
kubectl get pods -n default -l app=nginx-thrift
```

**Expected:** All show `Running` and `1/1` (or `2/2`)

---

### 3. Check Service Endpoints

```bash
kubectl get endpoints -n default | grep -E "(user-service|unique-id-service|nginx-thrift)"
```

**Expected:** Each service has at least one IP address listed

---

### 4. Check if Services are Listening on Ports

```bash
# Check user-service port 9090
USER_POD=$(kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $USER_POD -- /bin/sh -c "cat /proc/net/tcp | grep ':2388' && echo '✓ Port 9090 is listening' || echo '✗ Port 9090 NOT listening'"

# Check nginx-thrift port 8080
NGINX_POD=$(kubectl get pods -n default -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $NGINX_POD -- /bin/sh -c "cat /proc/net/tcp | grep ':1F90' && echo '✓ Port 8080 is listening' || echo '✗ Port 8080 NOT listening'"
```

**Expected:** Both show "Port is listening"

---

### 5. Check Service-to-Service Connectivity

```bash
NGINX_POD=$(kubectl get pods -n default -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $NGINX_POD -- /bin/sh -c "timeout 2 bash -c '</dev/tcp/user-service.default.svc.cluster.local/9090' 2>&1 && echo '✓ Connection successful' || echo '✗ Connection failed'"
```

**Expected:** "Connection successful"

---

### 6. Check HTTP Endpoint

```bash
# Make sure port-forward is running first:
# kubectl port-forward -n default svc/nginx-thrift-service 8080:8080

curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:8080/wrk2-api/user/register -X POST -d "test=1"
```

**Expected:** HTTP Status 400 or 500 (endpoint exists, request was invalid - this is OK)

---

### 7. Check for Initialization Errors

```bash
USER_POD=$(kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n default $USER_POD --tail=20 | grep -E "(error|Error|Failed)" | tail -5
```

**Expected:** No repeated "Failed to create mongodb index" errors

---

### 8. Check Database Status

```bash
# Check user-mongodb
kubectl get pods -n default -l app=user-mongodb

# Check MongoDB is ready
kubectl get pods -n default -l app=user-mongodb -o jsonpath='{.items[0].status.phase}'
```

**Expected:** `Running`

---

## Quick One-Liner Checks

### All Pods Ready?
```bash
kubectl get pods -n default -l 'app in (compose-post-service,home-timeline-service,media-service,nginx-thrift,post-storage-service,social-graph-service,text-service,unique-id-service,url-shorten-service,user-mention-service,user-service,user-timeline-service)' --no-headers | grep -v "Running.*1/1" | wc -l
```

**Expected:** `0` (no unready pods)

### Any CrashLoopBackOff?
```bash
kubectl get pods -n default | grep CrashLoopBackOff
```

**Expected:** No output (no crashing pods)

### Any Pending Pods?
```bash
kubectl get pods -n default | grep Pending
```

**Expected:** No output (no pending pods)

---

## What to Look For

### ✅ Good Signs:
- All pods show `Running` and `1/1` (or `2/2`)
- Services have endpoints configured
- Ports are listening
- No repeated error messages in logs
- Services can connect to each other

### ❌ Bad Signs:
- Pods showing `0/1` (not ready)
- `CrashLoopBackOff` status
- `Pending` status
- No endpoints for services
- Ports not listening
- Repeated MongoDB errors
- Connection refused errors

---

## If Something is Wrong

### Pods Not Ready:
```bash
# Check pod details
kubectl describe pod -n default <pod-name>

# Check pod logs
kubectl logs -n default <pod-name>
```

### MongoDB Errors:
```bash
# Reset MongoDB
kubectl delete pod -n default -l app=user-mongodb
kubectl wait --for=condition=ready pod -n default -l app=user-mongodb --timeout=60s

# Restart user-service
kubectl delete pod -n default -l app=user-service
```

### Port Not Listening:
```bash
# Service may be stuck initializing
# Check logs for errors
kubectl logs -n default <pod-name> --tail=50

# Restart the service
kubectl delete pod -n default -l app=<service-name>
```

---

## Ready for Testing?

Run the verification script:
```bash
./scripts/verify-system-ready.sh
```

If all checks pass, you're ready to run your peak test! 🚀

