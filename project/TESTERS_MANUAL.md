# Tester's Manual: DeathStarBench Social Network Autoscaling Tests

This manual provides step-by-step instructions for setting up and running autoscaling tests on the DeathStarBench social network application.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Pre-Test Checklist](#pre-test-checklist)
4. [Running Tests](#running-tests)
5. [Between Tests (Resetting Environment)](#between-tests-resetting-environment)
6. [Troubleshooting](#troubleshooting)
7. [Common Issues and Solutions](#common-issues-and-solutions)

---

## Prerequisites

### Required Tools
- `kubectl` configured to access your Kubernetes cluster
- `k6` installed for load testing
- Access to the cluster with appropriate permissions

### Required Services
- Kubernetes cluster (GKE, local, etc.)
- All microservice images built and pushed to registry
- MongoDB, Redis, Memcached available in cluster

---

## Initial Setup

### Step 1: Deploy All Services

Deploy all Kubernetes resources:

```bash
cd deathstarbench-socialnetwork/project

# Deploy all services, databases, and configurations
kubectl apply -f kubernetes/deployments/
kubectl apply -f kubernetes/services/
kubectl apply -f kubernetes/configmaps/
```

### Step 2: Deploy Autoscaling Rules

Deploy HPA (Horizontal Pod Autoscaler) rules:

```bash
# Deploy all HPA rules
kubectl apply -f kubernetes/autoscaling/hpa/

# Verify HPAs are created
kubectl get hpa -n default
```

**Note:** HPA changes take effect immediately - you do **not** need to restart pods when updating HPA configurations. The HPA controller automatically picks up changes.

### Step 3: Wait for Services to be Ready

Wait for all pods to be running:

```bash
# Watch pod status
kubectl get pods -w

# Or check specific services
kubectl get pods -n default -l app=user-service
kubectl get pods -n default -l app=nginx-thrift
```

**Expected time:** 2-5 minutes for all services to start

---

## Pre-Test Checklist

**ALWAYS run this before starting any test!**

### Step 1: Reset Databases (Critical)

Between tests, databases can accumulate stale data that causes:
- Duplicate key errors
- MongoDB index creation loops
- Service initialization failures

**Reset all databases:**

```bash
./scripts/reset-all-databases.sh
```

This script will:
- Delete all MongoDB PVCs (clearing all data)
- Recreate fresh databases
- Restart services to initialize with clean databases
- Wait for services to be ready

**Expected time:** 3-5 minutes

### Step 2: Restart All Pods (If Configuration Changed)

**IMPORTANT:** If you've updated deployment configurations (CPU requests, memory limits, readiness probes, etc.), you **must** restart the pods for changes to take effect.

**When to restart:**
- After updating deployment YAML files (CPU, memory, environment variables, etc.)
- After applying new deployment configurations: `kubectl apply -f kubernetes/deployments/`
- When pods need to pick up new resource requests/limits

**Restart all pods:**
```bash
./scripts/quick-restart-all-pods.sh
```

This ensures all pods are running with the latest configuration.

**Expected time:** 1-2 minutes

**Verify pods are running after restart:**
```bash
# Check pod status
kubectl get pods -n default

# Check specific service (e.g., user-service)
kubectl get pods -n default -l app=user-service

# Detailed pod information (shows resource requests, limits, status)
kubectl describe pod -n default <pod-name>

# Or for all pods of a service
kubectl describe pods -n default -l app=user-service
```

**What to look for:**
- Status should be `Running`
- Ready should show `1/1` (or `2/2` if multiple containers)
- In `kubectl describe`, check:
  - `Requests:` should show your updated CPU/memory values
  - `Limits:` should show your updated limits
  - `Conditions:` should show `Ready: True`

### Step 3: Verify System Readiness

Run the comprehensive verification script:

```bash
./scripts/verify-system-ready.sh
```

This checks:
- ✓ All critical pods are Running and Ready
- ✓ Service endpoints are configured
- ✓ Databases are accessible
- ✓ Services are listening on ports
- ✓ Service-to-service connectivity
- ✓ HTTP gateway is responding
- ✓ No MongoDB index creation loops
- ✓ No connection errors

**If verification fails:** See [Troubleshooting](#troubleshooting) section

### Step 4: Start Port Forwarding

Start port forwarding for the HTTP gateway:

```bash
# In a separate terminal
kubectl port-forward -n default svc/nginx-thrift-service 8080:8080
```

Keep this terminal open during tests.

---

## Running Tests

### Available Tests

1. **quick-test**: Low load validation (10 VUs, 20s)
   - Purpose: Verify system works at normal load
   - Expected: 100% success rate

2. **peak-test**: High load spike test (1000 VUs, 7 minutes)
   - Purpose: Trigger autoscaling and measure performance
   - Expected: Some failures under extreme load (expected behavior)

3. **sweet-test**: ⭐ **Recommended for autoscaling demo** (350 VUs, 9 minutes)
   - Purpose: Demonstrates autoscaling under challenging but achievable load
   - Expected: >85% success rate, clear autoscaling behavior visible
   - Best for: Proving autoscaling works without overwhelming the system

### Running a Test

```bash
# Run quick test
./scripts/run-k6-tests.sh quick-test

# Run peak test (very aggressive)
./scripts/run-k6-tests.sh peak-test

# Run sweet-test (recommended for autoscaling demo)
./scripts/run-k6-tests.sh sweet-test
```

### Monitoring During Tests

**In separate terminals, monitor:**

1. **HPA Status:**
   ```bash
   watch -n 2 'kubectl get hpa -n default'
   ```

2. **HPA Details (Scale Up/Down Delays):**
   ```bash
   # Describe specific HPA (shows scale up/down stabilization windows and policies)
   kubectl describe hpa <hpa-name> -n default
   
   # Example: Check user-service HPA
   kubectl describe hpa user-service-hpa -n default
   
   # Check all HPAs at once
   for hpa in $(kubectl get hpa -n default -o name); do
     echo "=== $hpa ==="
     kubectl describe $hpa -n default | grep -A 10 "Behavior:"
   done
   ```
   
   **What to look for:**
   - `Scale Up:` section shows `stabilizationWindowSeconds` (how long before scaling up again)
   - `Scale Down:` section shows `stabilizationWindowSeconds` (how long before scaling down)
   - `Policies:` show how many pods can be added/removed per period

2. **Pod Counts:**
   ```bash
   watch -n 2 'kubectl get pods -n default | grep -E "(user-service|unique-id-service|social-graph-service|nginx-thrift)"'
   ```

3. **HPA Details (Scale Up/Down Configuration):**
   ```bash
   # Check specific HPA configuration (shows scale up/down delays)
   kubectl describe hpa user-service-hpa -n default
   kubectl describe hpa unique-id-service-hpa -n default
   
   # Quick view of all HPA scale-down windows
   kubectl get hpa -n default -o custom-columns=NAME:.metadata.name,SCALE_UP:.spec.behavior.scaleUp.stabilizationWindowSeconds,SCALE_DOWN:.spec.behavior.scaleDown.stabilizationWindowSeconds
   ```
   
   **Key information:**
   - Scale-up `stabilizationWindowSeconds`: How long HPA waits before scaling up again (0 = immediate)
   - Scale-down `stabilizationWindowSeconds`: How long HPA waits before scaling down (60s = 1 minute for cost optimization)
   - Policies: How many pods can be added/removed per time period

4. **Resource Usage:**
   ```bash
   watch -n 2 'kubectl top pods -n default'
   ```

5. **Service Logs:**
   ```bash
   # User service
   kubectl logs -n default -l app=user-service -f
   
   # Nginx gateway
   kubectl logs -n default -l app=nginx-thrift -f
   ```

### Test Results

Test results are saved to:
- `k6-results/<test-name>_<timestamp>.json` - Full JSON results
- `k6-results/<test-name>_<timestamp>_summary.txt` - Human-readable summary
- `k6-results/<test-name>_<timestamp>_metrics.csv` - Extracted metrics

---

## Between Tests (Resetting Environment)

**IMPORTANT:** Always reset between tests to prevent stale data issues.

### Complete Reset Procedure

1. **Reset All Databases:**
   ```bash
   ./scripts/reset-all-databases.sh
   ```
   This is the most critical step. Stale MongoDB data causes:
   - Duplicate key errors
   - Index creation loops
   - Service initialization failures

2. **Restart Pods (if needed):**
   ```bash
   ./scripts/quick-restart-all-pods.sh
   ```
   **Required** if you've changed deployment configurations (CPU, memory, etc.). Pods must be restarted to pick up new resource requests/limits.
   
   **Verify pods restarted successfully:**
   ```bash
   # Check pod status
   kubectl get pods -n default -l app=user-service
   
   # Detailed information (shows updated resource requests/limits)
   kubectl describe pod -n default <pod-name>
   ```

3. **Verify System:**
   ```bash
   ./scripts/verify-system-ready.sh
   ```
   Ensure everything is ready before the next test.

4. **Wait for Stabilization:**
   - Wait 1-2 minutes after reset for services to fully initialize
   - Check that all pods are `Running` and `Ready`

---

## Troubleshooting

### Verification Script Fails

If `verify-system-ready.sh` reports failures:

1. **Check pod status:**
   ```bash
   kubectl get pods -n default
   ```

2. **Check pod logs:**
   ```bash
   kubectl logs -n default <pod-name>
   ```

3. **Check pod events:**
   ```bash
   kubectl describe pod -n default <pod-name>
   ```

### MongoDB Index Creation Loop

**Symptoms:**
- Service logs show repeated "Failed to create mongodb index" errors
- Service never becomes ready
- Connection refused errors from other services

**Solution:**
```bash
./scripts/reset-all-databases.sh
```

This resets the database and clears corrupted index state.

### Connection Refused Errors

**Symptoms:**
- nginx-thrift cannot connect to user-service
- user-service cannot connect to social-graph-service
- Services are running but not accepting connections

**Solutions:**

1. **Check if services are listening:**
   ```bash
   # Check user-service
   kubectl exec -n default <user-service-pod> -- pgrep -f UserService
   
   # Check social-graph-service
   kubectl exec -n default <social-graph-pod> -- pgrep -f SocialGraphService
   ```

2. **Check readiness probes:**
   ```bash
   kubectl describe pod -n default <pod-name> | grep -A 5 "Readiness"
   ```

3. **Restart services:**
   ```bash
   ./scripts/quick-restart-all-pods.sh
   ```

4. **Reset databases (if MongoDB issues):**
   ```bash
   ./scripts/reset-all-databases.sh
   ```

### High Failure Rate During Tests

**If failure rate > 50%:**

1. **Check if it's capacity-related (expected):**
   - Look at test results: Are successful requests fast (< 500ms)?
   - Are failures mostly timeouts (10+ seconds)?
   - If yes, this is expected under extreme load (1000 VUs)

2. **Check if it's a critical error:**
   - Look for "connection refused" errors in logs
   - Check for MongoDB index loops
   - Check if services crashed

3. **Verify system before test:**
   ```bash
   ./scripts/verify-system-ready.sh
   ```

### HPA Not Scaling

**Symptoms:**
- CPU/Memory usage high but pods not scaling
- HPA shows "No recommendation" or warnings

**Solutions:**

1. **Check metrics-server:**
   ```bash
   kubectl get pods -n kube-system | grep metrics-server
   kubectl top nodes
   ```

2. **Check HPA status and configuration:**
   ```bash
   # Detailed HPA information (shows scale up/down delays, policies, current metrics)
   kubectl describe hpa <hpa-name> -n default
   
   # Quick view of scale up/down windows for all HPAs
   kubectl get hpa -n default -o custom-columns=NAME:.metadata.name,SCALE_UP:.spec.behavior.scaleUp.stabilizationWindowSeconds,SCALE_DOWN:.spec.behavior.scaleDown.stabilizationWindowSeconds
   
   # Example: Check user-service HPA
   kubectl describe hpa user-service-hpa -n default
   ```

3. **Check pod resource requests:**
   ```bash
   kubectl describe pod -n default <pod-name> | grep -A 5 "Requests"
   ```
   HPAs need resource requests to calculate utilization.

---

## Common Issues and Solutions

### Issue: "Duplicate key error" in MongoDB

**Cause:** Stale data from previous tests

**Solution:**
```bash
./scripts/reset-all-databases.sh
```

### Issue: Service stuck in "0/1 Running"

**Cause:** Readiness probe failing or service not initializing

**Solutions:**
1. Check logs: `kubectl logs -n default <pod-name>`
2. Check readiness probe: `kubectl describe pod -n default <pod-name>`
3. If MongoDB errors: `./scripts/reset-all-databases.sh`
4. Restart pod: `kubectl delete pod -n default <pod-name>`

### Issue: Port forwarding fails

**Cause:** Port 8080 already in use or service not ready

**Solutions:**
1. Check if port is in use: `lsof -i :8080`
2. Kill existing port-forward: Find process and kill it
3. Verify service is ready: `kubectl get svc nginx-thrift-service -n default`
4. Restart port-forward: `kubectl port-forward -n default svc/nginx-thrift-service 8080:8080`

### Issue: All tests fail with 100% error rate

**Cause:** Critical system failure (MongoDB index loop, service not listening)

**Solution:**
1. Run verification: `./scripts/verify-system-ready.sh`
2. Check for MongoDB index loops in logs
3. Reset databases: `./scripts/reset-all-databases.sh`
4. Restart all pods: `./scripts/quick-restart-all-pods.sh`
5. Verify again: `./scripts/verify-system-ready.sh`

### Issue: Tests pass but autoscaling doesn't happen

**Cause:** HPA not configured or metrics not available

**Solutions:**
1. Check HPA exists: `kubectl get hpa -n default`
2. Check HPA status: `kubectl describe hpa <hpa-name> -n default`
3. Check metrics-server: `kubectl top pods -n default`
4. Check pod resource requests (required for HPA)

---

## Quick Reference: Essential Commands

### Before Every Test
```bash
./scripts/reset-all-databases.sh
./scripts/verify-system-ready.sh
kubectl port-forward -n default svc/nginx-thrift-service 8080:8080
```

### During Tests
```bash
# Monitor HPAs
watch -n 2 'kubectl get hpa -n default'

# Monitor HPA details (scale up/down delays)
kubectl describe hpa user-service-hpa -n default
kubectl describe hpa unique-id-service-hpa -n default

# Monitor pods
watch -n 2 'kubectl get pods -n default'

# Monitor resources
watch -n 2 'kubectl top pods -n default'
```

### After Tests
```bash
# Check results
ls -lh k6-results/

# Reset for next test
./scripts/reset-all-databases.sh
```

---

## Script Reference

### Core Scripts

- **`verify-system-ready.sh`**: Comprehensive system verification
- **`reset-all-databases.sh`**: Reset all MongoDB databases (CRITICAL between tests)
- **`quick-restart-all-pods.sh`**: Restart all service pods
- **`run-k6-tests.sh`**: Run k6 load tests

### Utility Scripts

- **`reset-mongodb-database.sh`**: Reset only user-mongodb
- **`reset-social-graph-mongodb.sh`**: Reset only social-graph-mongodb
- **`diagnose-cluster-overload.sh`**: Diagnose cluster resource issues
- **`check-node-capacity.sh`**: Check node CPU/memory capacity

---

## Best Practices

1. **Always reset databases between tests** - Prevents stale data issues
2. **Always verify system before tests** - Catches issues early
3. **Monitor during tests** - Watch HPAs, pods, and logs
4. **Keep port-forward running** - Required for tests to work
5. **Check logs when issues occur** - Most issues are visible in logs
6. **Reset after configuration changes** - Ensures new config is applied

---

## Success Criteria

### Quick Test Should Show:
- ✓ 100% success rate (0% failures)
- ✓ p50 latency < 500ms
- ✓ p95 latency < 1000ms
- ✓ All checks pass

### Peak Test Should Show:
- ✓ Autoscaling triggered (pods scale up)
- ✓ Some failures under extreme load (expected)
- ✓ Successful requests are fast (< 500ms)
- ✓ No critical errors (connection refused, index loops)
- ✓ System recovers after load spike

---

## Getting Help

If you encounter issues not covered in this manual:

1. Check pod logs: `kubectl logs -n default <pod-name>`
2. Check pod events: `kubectl describe pod -n default <pod-name>`
3. Run verification: `./scripts/verify-system-ready.sh`
4. Check HPA status: `kubectl describe hpa -n default`
5. Review test results in `k6-results/` directory

---

**Last Updated:** 2025-12-06
**Version:** 1.0

