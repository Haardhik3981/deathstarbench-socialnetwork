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

### Step 2: Apply Deployment Changes and Restart Pods (If Configuration Changed)

**IMPORTANT:** If you've updated deployment YAML files (CPU requests, memory limits, readiness probes, etc.), you **must** follow this complete workflow for changes to take effect.

**When to apply and restart:**
- After updating deployment YAML files (CPU, memory, environment variables, etc.)
- After modifying resource requests/limits
- After changing readiness probes or other pod configurations

**Complete workflow:**

1. **Apply the updated deployment YAML files:**
   ```bash
   # Apply specific deployment(s) you changed
   kubectl apply -f kubernetes/deployments/user-service-deployment.yaml
   kubectl apply -f kubernetes/deployments/social-graph-service-deployment.yaml
   kubectl apply -f kubernetes/deployments/compose-post-service-deployment.yaml
   
   # Or apply all deployments at once
   kubectl apply -f kubernetes/deployments/
   ```
   
   This updates the Deployment specification in Kubernetes, but **existing pods keep their old configuration**.

2. **Restart all pods to pick up new configuration:**
   ```bash
   ./scripts/quick-restart-all-pods.sh
   ```
   
   This deletes existing pods, forcing Kubernetes to recreate them with the updated Deployment spec (new resource requests/limits, etc.).

3. **Verify the changes took effect:**
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

**Expected time:** 1-2 minutes for pods to restart and become ready

**Note:** Simply applying YAML files is not enough - pods must be restarted to pick up new resource configurations. The `kubectl apply` command updates the Deployment spec, but existing pods continue running with their original configuration until they are recreated.

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

2. **constant-load**: Steady baseline load (50 VUs, 3 minutes)
   - Purpose: Establish baseline performance metrics
   - Expected: 100% success rate

3. **peak-test**: High load spike test (1000 VUs, 7 minutes)
   - Purpose: Trigger autoscaling and measure performance
   - Expected: Some failures under extreme load (expected behavior)

4. **sweet-test**: ⭐ **Recommended for autoscaling demo** (1000 VUs peak, 18 minutes)
   - Purpose: Demonstrates autoscaling under challenging but achievable load
   - Expected: >85% success rate, clear autoscaling behavior visible
   - Best for: Proving autoscaling works without overwhelming the system

5. **stress-test**: Gradual ramp-up test (400 VUs peak, 40 minutes)
   - Purpose: Find breaking points and observe gradual scaling
   - Expected: Performance degradation as load increases

6. **endurance-test**: Long-duration stability test (200 VUs, 2.5 hours)
   - Purpose: Identify memory leaks and long-term issues
   - Expected: Stable performance over extended period

7. **cpu-intensive-test**: CPU-focused workload (1000 VUs peak, 17 minutes)
   - Purpose: Test CPU-based autoscaling specifically
   - Expected: CPU usage triggers scaling before memory

### Running a Test

**Use the `run-test-with-metrics.sh` script** to run tests with automatic metric extraction and timestamp recording:

```bash
# Run quick test (low load validation)
./scripts/run-test-with-metrics.sh quick-test

# Run constant-load test (baseline performance)
./scripts/run-test-with-metrics.sh constant-load

# Run sweet-test (⭐ recommended for HPA autoscaling demo)
./scripts/run-test-with-metrics.sh sweet-test

# Run peak-test (high load spike)
./scripts/run-test-with-metrics.sh peak-test

# Run stress-test (gradual ramp-up to find breaking point)
./scripts/run-test-with-metrics.sh stress-test

# Run endurance-test (long duration stability test)
./scripts/run-test-with-metrics.sh endurance-test

# Run cpu-intensive-test (CPU-focused autoscaling test)
./scripts/run-test-with-metrics.sh cpu-intensive-test
```

**With custom BASE_URL:**
```bash
BASE_URL=http://localhost:8080 ./scripts/run-test-with-metrics.sh sweet-test
```

**List all available tests:**
```bash
./scripts/run-test-with-metrics.sh --help
```

**What the script does:**
- Runs the k6 test with JSON and summary output
- Records test start/end timestamps (UTC) for Prometheus/Grafana correlation
- Extracts key metrics automatically
- Saves results to `k6-results/<test-name>_<timestamp>.json` and `_summary.txt`
- Provides time range for Prometheus/Grafana queries

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

3. **Pod Counts:**
   ```bash
   watch -n 2 'kubectl get pods -n default | grep -E "(user-service|unique-id-service|social-graph-service|nginx-thrift)"'
   ```

4. **VPA Status:**
   ```bash
   # Watch VPA recommendations
   watch -n 5 'kubectl get vpa -n default'
   ```
   
   Shows current VPA recommendations for all services.

5. **VPA Details (Recommendations and Pod Recreation):**
   ```bash
   # Check specific VPA recommendations (shows target, uncapped target, bounds)
   kubectl describe vpa user-service-vpa -n default
   kubectl describe vpa unique-id-service-vpa -n default
   
   # Quick view of all VPA recommendations
   kubectl get vpa -n default -o custom-columns=NAME:.metadata.name,MODE:.spec.updatePolicy.updateMode,TARGET_CPU:.status.recommendation.containerRecommendations[0].target.cpu,TARGET_MEM:.status.recommendation.containerRecommendations[0].target.memory
   
   # Or use the watch script (more user-friendly)
   ./scripts/watch-vpa.sh user-service    # Watch single service
   ./scripts/watch-vpa.sh all             # Watch all services with VPAs
   ./scripts/watch-vpa.sh                 # Watch all services (default)
   ```
   
   **Key information:**
   - `updateMode`: How VPA applies recommendations (Recreate, Initial, Auto, Off)
   - `Target`: Current recommended CPU/memory (constrained by minAllowed/maxAllowed)
   - `Uncapped Target`: What VPA would recommend without constraints (shows if VPA has learned)
   - `Lower Bound` / `Upper Bound`: Min/max recommendations based on constraints
   - **Pod Recreation**: In Recreate mode, check pod `AGE` to see if pods were recreated with new resources
   - **Resource Changes**: Compare pod `CPU_REQ`/`MEM_REQ` before and after to see if VPA updated them

6. **Resource Usage:**
   ```bash
   watch -n 2 'kubectl top pods -n default'
   ```

7. **Service Logs:**
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

2. **Apply Deployment Changes (if you modified YAML files):**
   ```bash
   # Apply the updated deployment(s)
   kubectl apply -f kubernetes/deployments/<deployment-name>.yaml
   
   # Or apply all deployments
   kubectl apply -f kubernetes/deployments/
   ```

3. **Restart Pods (if configuration changed):**
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

4. **Verify System:**
   ```bash
   ./scripts/verify-system-ready.sh
   ```
   
   Ensure everything is ready before the next test. This checks that pods are running with the new configuration and all services are healthy.

5. **Wait for Stabilization:**
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

### VPA Not Scaling or Not Learning

**Symptoms:**
- VPA recommendations don't change after running tests
- Uncapped Target remains very low (e.g., 4m CPU)
- Pods not being recreated with new resources

**Solutions:**

1. **Check VPA components are running:**
   ```bash
   kubectl get pods -n kube-system | grep vpa
   ```
   Should see: `vpa-recommender`, `vpa-updater`, `vpa-admission-controller`

2. **Check VPA status and recommendations:**
   ```bash
   # Detailed VPA information (shows recommendations, uncapped target, bounds)
   kubectl describe vpa <vpa-name> -n default
   
   # Example: Check user-service VPA
   kubectl describe vpa user-service-vpa -n default
   
   # Check if VPA has recommendations
   kubectl get vpa -n default -o custom-columns=NAME:.metadata.name,RECOMMENDATION:.status.recommendation
   ```

3. **Check VPA recommender logs:**
   ```bash
   kubectl logs -n kube-system -l app=vpa-recommender --tail=50
   ```
   Look for errors or warnings about metrics collection.

4. **Verify VPA has enough data:**
   - VPA needs 10-15 minutes of sustained load to learn
   - Check `Uncapped Target` - if it's very low (4m CPU), VPA hasn't seen high load yet
   - Run longer warmup period (use `endurance-test.js`)

5. **Check VPA update mode:**
   ```bash
   kubectl get vpa -n default -o custom-columns=NAME:.metadata.name,MODE:.spec.updatePolicy.updateMode
   ```
   - `Recreate`: Pods will be recreated with new resources (may take time)
   - `Initial`: Only sets resources when pods are first created
   - `Off`: Only provides recommendations, doesn't apply them

6. **Check if pods were recreated (Recreate mode):**
   ```bash
   # Check pod creation timestamps
   kubectl get pods -l app=user-service -n default --sort-by=.metadata.creationTimestamp
   ```
   New pods indicate VPA triggered recreation.

7. **Verify metrics are being collected:**
   ```bash
   # Check if metrics-server is working
   kubectl top pods -n default
   
   # Check VPA can see pod metrics
   kubectl logs -n kube-system -l app=vpa-recommender | grep -i "metrics"
   ```

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
# 1. Reset databases (CRITICAL)
./scripts/reset-all-databases.sh

# 2. Apply deployment changes (if you modified YAML files)
kubectl apply -f kubernetes/deployments/

# 3. Restart pods (if configuration changed)
./scripts/quick-restart-all-pods.sh

# Check pod requests and limits
kubectl get pods -n default -o json | \
  jq -r '.items[] | 
    "\(.metadata.name)\t\(.spec.containers[0].resources.requests.cpu // "N/A")\t\(.spec.containers[0].resources.limits.cpu // "N/A")\t\(.spec.containers[0].resources.requests.memory // "N/A")\t\(.spec.containers[0].resources.limits.memory // "N/A")"'

# 4. Verify system is ready
./scripts/verify-system-ready.sh

# 5. Start port-forward (in separate terminal)
kubectl port-forward -n default svc/nginx-thrift-service 8080:8080
```

### During Tests

```bash
# Monitor HPAs
watch -n 2 'kubectl get hpa -n default'

# Monitor HPA details (scale up/down delays)
kubectl describe hpa user-service-hpa -n default
kubectl describe hpa unique-id-service-hpa -n default

# Monitor VPAs
watch -n 5 'kubectl get vpa -n default'

# Monitor VPA details (recommendations and pod recreation)
kubectl describe vpa user-service-vpa -n default
./scripts/watch-vpa.sh all              # Watch all services (recommended)
./scripts/watch-vpa.sh user-service     # Watch single service

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
- **`run-test-with-metrics.sh`**: ⭐ **Run k6 load tests with automatic metric extraction** (recommended)
- **`run-k6-tests.sh`**: Alternative script for running k6 tests (legacy)

### Utility Scripts

- **`reset-mongodb-database.sh`**: Reset only user-mongodb
- **`reset-social-graph-mongodb.sh`**: Reset only social-graph-mongodb
- **`diagnose-cluster-overload.sh`**: Diagnose cluster resource issues
- **`check-node-capacity.sh`**: Check node CPU/memory capacity

---

## Best Practices

1. **Always reset databases between tests** - Prevents stale data issues
2. **Apply deployment changes before restarting pods** - Use `kubectl apply -f kubernetes/deployments/` to update Deployment specs
3. **Always restart pods after configuration changes** - Pods must be recreated to pick up new resource requests/limits
4. **Always verify system before tests** - Catches issues early and confirms new configuration is active
5. **Monitor during tests** - Watch HPAs, pods, and logs
6. **Keep port-forward running** - Required for tests to work
7. **Check logs when issues occur** - Most issues are visible in logs

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
