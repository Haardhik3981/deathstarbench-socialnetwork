# 🚀 Complete K6 Testing Plan - System Stability & Bottleneck Analysis

## 📋 Test Suite Overview

| Test | Duration | Max Users | Purpose | Order |
|------|----------|-----------|---------|-------|
| **Load** | 14 min | 100 | Baseline performance | 1st |
| **Spike** | 10 min | 500 | Sudden traffic bursts | 2nd |
| **Stress** | 15 min | 600 | Find breaking point | 3rd |
| **Soak** | 30 min | 75 | Find memory leaks | 4th |

**Total Time:** ~80 minutes + recovery periods

---

## ✅ Prerequisites

**Verify everything is running:**

```bash
# All pods should be 2/2 Running (including nginx-thrift!)
kubectl get pods -n cse239fall2025 | grep -E "nginx|timeline|post|compose|storage|graph|text|user|unique|url|mention"

# Prometheus targets 10/10 UP
open http://localhost:9090/targets

# Grafana accessible
open http://localhost:3000
```

**Critical:** nginx-thrift MUST show `2/2 Running`!

---

## 🧪 Test 1: Load Test (14 minutes)

**Purpose:** Establish baseline performance under normal expected load

**Load Pattern:**
- Ramp to 50 users (2 min)
- Sustain 50 users (5 min)
- Ramp to 100 users (2 min)
- Sustain 100 users (3 min)
- Ramp down (2 min)

### Commands:

```bash
cd "/Users/haardhikmudagereanil/Downloads/MSCS - UCSC/Q4/CSE239_AdvCloudComputing/Project/DeathStarBench_project_root/DeathStarBench/socialNetwork/helm-chart/scripts"

# Deploy ConfigMap
kubectl apply -f k6-configmap.yaml -n cse239fall2025

# Start load test
kubectl apply -f k6-job.yaml -n cse239fall2025

# Watch progress
kubectl logs -f -n cse239fall2025 -l app=k6-load-test
```

### What to Monitor in Grafana:

**Open:** http://localhost:3000

**Watch:**
- Total CPU: Should go from 0.01 → 0.03-0.05 cores
- nginx-thrift CPU: 0.001 → 0.005-0.01 cores
- Service CPUs: All should increase
- Memory: Gradual increase, should stabilize
- Throughput: 25-35 req/s

### Expected Results:

```
✅ Total Requests:      20,000-25,000
✅ Success Rate:        > 95%
✅ Error Rate:          < 5%
✅ p95 Latency:         < 500ms
✅ p99 Latency:         < 1000ms
✅ Throughput:          25-35 req/s
```

### Get Results:

```bash
# Wait for test to complete (14 min)
kubectl wait --for=condition=complete --timeout=20m job/k6-load-test -n cse239fall2025

# View results
kubectl logs -n cse239fall2025 -l app=k6-load-test | tail -100

# Save results
kubectl logs -n cse239fall2025 -l app=k6-load-test > load-test-results.txt
```

---

## 🚀 Test 2: Spike Test (10 minutes)

**Purpose:** Test system response to sudden traffic spikes

**Load Pattern:**
- Normal: 50 users
- **SPIKE 1:** Jump to 300 users (6x!)
- **SPIKE 2:** Jump to 400 users (8x!)
- **SPIKE 3:** Jump to 500 users (10x!)

**Wait 5 minutes after Load Test:**

```bash
echo "Waiting 5 minutes for system recovery..."
sleep 300
```

### Commands:

```bash
# Clean up previous test
kubectl delete job k6-load-test -n cse239fall2025

# Start spike test
kubectl apply -f k6-spike-job.yaml -n cse239fall2025

# Watch progress
kubectl logs -f -n cse239fall2025 -l app=k6-spike-test
```

### What to Monitor in Grafana:

**Watch for:**
- **Sudden CPU spikes** during each jump
- **Memory spikes** (should recover between spikes)
- **Throughput jumps** to 150-250+ req/s
- **Service throttling** (which services max out first)
- **HPA triggering** (if enabled - pod count increases)

### Expected Results:

```
⚠️  Total Requests:      80,000-120,000
⚠️  Success Rate:        70-90% (spikes cause errors)
⚠️  Error Rate:          10-30% (acceptable for spike test)
⚠️  p95 Latency:         1-5s during spikes
✅  Recovery:            System recovers between spikes
```

### Get Results:

```bash
# Wait for completion (10 min)
kubectl wait --for=condition=complete --timeout=15m job/k6-spike-test -n cse239fall2025

# View results
kubectl logs -n cse239fall2025 -l app=k6-spike-test | tail -100

# Save results
kubectl logs -n cse239fall2025 -l app=k6-spike-test > spike-test-results.txt
```

---

## 🔥 Test 3: Stress Test (15 minutes)

**Purpose:** Find the absolute breaking point of the system

**Load Pattern:**
- Progressive ramp: 50 → 100 → 200 → 300 → 400 → 500 → 600 users

**Wait 5 minutes after Spike Test:**

```bash
echo "Waiting 5 minutes for system recovery..."
sleep 300
```

### Commands:

```bash
# Clean up previous test
kubectl delete job k6-spike-test -n cse239fall2025

# Start stress test
kubectl apply -f k6-stress-job.yaml -n cse239fall2025

# Watch progress
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test
```

### What to Monitor in Grafana:

**Critical Metrics:**
- **CPU hitting 100%** - At what user count?
- **Memory exhaustion** - Any OOMKilled?
- **Error rate climbing** - Breaking point identification
- **Response time degradation** - When does p95 exceed 5s?
- **Pod crashes** - Any services failing?

### Expected Results:

```
⚠️  Total Requests:      140,000-150,000
⚠️  Success Rate:        90-95%
⚠️  Error Rate:          5-10%
⚠️  p95 Latency:         5-10s at peak
⚠️  Breaking Point:      ~400-500 users
🔥  Max Throughput:      140-180 req/s
```

### Get Results:

```bash
# Wait for completion (15 min)
kubectl wait --for=condition=complete --timeout=20m job/k6-stress-test -n cse239fall2025

# View results
kubectl logs -n cse239fall2025 -l app=k6-stress-test | tail -100

# Save results
kubectl logs -n cse239fall2025 -l app=k6-stress-test > stress-test-results.txt
```

---

## ⏱️ Test 4: Soak Test (30 minutes)

**Purpose:** Find memory leaks and resource exhaustion over time

**Load Pattern:**
- Ramp to 75 users (2 min)
- **Sustain 75 users for 26 minutes**
- Ramp down (2 min)

**Wait 10 minutes after Stress Test:**

```bash
echo "Waiting 10 minutes for full system recovery..."
sleep 600
```

### Commands:

```bash
# Clean up previous test
kubectl delete job k6-stress-test -n cse239fall2025

# Start soak test (30 min!)
kubectl apply -f k6-soak-job.yaml -n cse239fall2025

# Watch progress
kubectl logs -f -n cse239fall2025 -l app=k6-soak-test
```

### What to Monitor in Grafana:

**Critical - Watch for Memory Leaks:**
- **Memory graph** - Should PLATEAU (not continuously climb)
- **CPU graph** - Should STABILIZE (not keep increasing)
- **Error rate** - Should stay LOW (< 5%)
- **Response times** - Should NOT degrade over time
- **Pod restarts** - Should be ZERO

**Memory Leak Indicators:**
- ❌ Memory continuously climbing (leak!)
- ❌ Response times increasing over time
- ❌ Error rate growing
- ❌ Pods restarting due to OOM

### Expected Results:

```
✅ Total Requests:      50,000-70,000
✅ Success Rate:        > 95%
✅ Error Rate:          < 5%
✅ p95 Latency:         < 500ms (stable throughout)
✅ Memory:              Plateaus after initial ramp
✅ CPU:                 Stable around same level
✅ No Pod Restarts:     0
```

### Get Results:

```bash
# Wait for completion (30 min)
kubectl wait --for=condition=complete --timeout=35m job/k6-soak-test -n cse239fall2025

# View results
kubectl logs -n cse239fall2025 -l app=k6-soak-test | tail -100

# Save results
kubectl logs -n cse239fall2025 -l app=k6-soak-test > soak-test-results.txt
```

---

## 📊 Monitoring Setup (Run Before Tests)

### Terminal 1: K6 Test Logs

```bash
cd scripts/
# Will be used for kubectl logs -f commands
```

### Terminal 2: Watch Pods

```bash
# Monitor pod status and restarts
watch -n 2 "kubectl get pods -n cse239fall2025 | grep -E 'NAME|nginx|timeline|post|compose|storage|graph|text|user|unique|url|mention'"
```

### Terminal 3: Monitor Resources

```bash
# Watch CPU/Memory in real-time
watch -n 2 "kubectl top pods -n cse239fall2025 | grep -E 'NAME|nginx|timeline|post|compose'"
```

### Browser: Grafana

**Open:** http://localhost:3000

**Set time range:** Last 1 hour, Auto-refresh: 5s

---

## 📈 Complete Test Session (All 4 Tests)

### Full Sequence:

```bash
cd "/Users/haardhikmudagereanil/Downloads/MSCS - UCSC/Q4/CSE239_AdvCloudComputing/Project/DeathStarBench_project_root/DeathStarBench/socialNetwork/helm-chart/scripts"

# Deploy all ConfigMaps
kubectl apply -f k6-configmap.yaml -n cse239fall2025
kubectl apply -f k6-spike-job.yaml -n cse239fall2025  # Contains ConfigMap
kubectl apply -f k6-stress-job.yaml -n cse239fall2025  # Contains ConfigMap
kubectl apply -f k6-soak-job.yaml -n cse239fall2025    # Contains ConfigMap

# Test 1: Load Test (14 min)
kubectl apply -f k6-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-load-test
kubectl wait --for=condition=complete --timeout=20m job/k6-load-test -n cse239fall2025
kubectl logs -n cse239fall2025 -l app=k6-load-test > load-test-results.txt

# Recovery (5 min)
echo "Recovery period..."
sleep 300

# Test 2: Spike Test (10 min)
kubectl delete job k6-load-test -n cse239fall2025
kubectl apply -f k6-spike-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-spike-test
kubectl wait --for=condition=complete --timeout=15m job/k6-spike-test -n cse239fall2025
kubectl logs -n cse239fall2025 -l app=k6-spike-test > spike-test-results.txt

# Recovery (5 min)
echo "Recovery period..."
sleep 300

# Test 3: Stress Test (15 min)
kubectl delete job k6-spike-test -n cse239fall2025
kubectl apply -f k6-stress-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test
kubectl wait --for=condition=complete --timeout=20m job/k6-stress-test -n cse239fall2025
kubectl logs -n cse239fall2025 -l app=k6-stress-test > stress-test-results.txt

# Recovery (10 min)
echo "Extended recovery period..."
sleep 600

# Test 4: Soak Test (30 min)
kubectl delete job k6-stress-test -n cse239fall2025
kubectl apply -f k6-soak-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-soak-test
kubectl wait --for=condition=complete --timeout=35m job/k6-soak-test -n cse239fall2025
kubectl logs -n cse239fall2025 -l app=k6-soak-test > soak-test-results.txt

echo "✅ All tests complete! Results saved."
ls -lh *-results.txt
```

---

## 📊 Analysis Framework

### After Each Test, Analyze:

#### **1. K6 Output Metrics:**
- Total requests
- Success rate
- Error rate
- Response times (p50, p95, p99)
- Throughput (req/s)

#### **2. Grafana Dashboards:**
- CPU usage patterns
- Memory consumption trends
- Service-level resource usage
- System load indicator

#### **3. Kubernetes Events:**
```bash
kubectl get events -n cse239fall2025 --sort-by='.lastTimestamp' | tail -50
```

#### **4. Pod Health:**
```bash
kubectl get pods -n cse239fall2025 | grep -E "nginx|timeline|post|compose" | awk '{print $1, $3, $4}'
```

---

## 🎯 What You're Looking For

### **Load Test - Baseline:**
- ✅ Establish normal performance metrics
- ✅ Verify all services handle expected load
- ✅ No errors or crashes
- ✅ Response times acceptable

### **Spike Test - Resilience:**
- ✅ System handles sudden traffic bursts
- ✅ Auto-scaling triggers appropriately
- ✅ Services recover between spikes
- ⚠️  Identify services that struggle with spikes

### **Stress Test - Limits:**
- ⚠️  Find breaking point (user count where error rate > 20%)
- ⚠️  Identify bottleneck services (first to max out)
- ⚠️  Observe graceful degradation
- ⚠️  Determine maximum safe capacity

### **Soak Test - Stability:**
- ✅ Memory usage plateaus (no leaks)
- ✅ CPU usage stable (no degradation)
- ✅ Error rate stays low (< 5%)
- ✅ No pod restarts or crashes
- ✅ Performance doesn't degrade over time

---

## 📈 Expected Timeline

```
00:00 - 00:14  Load Test       (Baseline)
00:14 - 00:19  Recovery
00:19 - 00:29  Spike Test      (Resilience)
00:29 - 00:34  Recovery
00:34 - 00:49  Stress Test     (Breaking Point)
00:49 - 00:59  Recovery
00:59 - 01:29  Soak Test       (Memory Leaks)
01:29          Complete!
```

**Total:** ~90 minutes

---

## 🔍 Bottleneck Identification

### During Tests, Monitor:

**Which service maxes out first?**
```bash
watch -n 2 "kubectl top pods -n cse239fall2025 | sort -k3 -nr | head -15"
```

**Resource usage ranking:**
- Look for services hitting 100% CPU
- Look for memory approaching limits
- Look for high restart counts

### Common Bottlenecks:

1. **nginx-thrift** - Gateway, handles all traffic
2. **compose-post-service** - Complex orchestration
3. **home-timeline-service** - Aggregates multiple feeds
4. **Databases** - MongoDB/Redis connections

---

## 💾 Save All Results

After all tests:

```bash
# Create results summary
cat > test-summary.txt << EOF
=== K6 Test Results Summary ===
Date: $(date)

Load Test Results:
$(kubectl logs -n cse239fall2025 -l app=k6-load-test 2>/dev/null | grep -A 20 "OVERALL RESULTS" || echo "No data")

Spike Test Results:
$(kubectl logs -n cse239fall2025 -l app=k6-spike-test 2>/dev/null | grep -A 20 "OVERALL RESULTS" || echo "No data")

Stress Test Results:
$(kubectl logs -n cse239fall2025 -l app=k6-stress-test 2>/dev/null | grep -A 20 "OVERALL RESULTS" || echo "No data")

Soak Test Results:
$(kubectl logs -n cse239fall2025 -l app=k6-soak-test 2>/dev/null | grep -A 20 "OVERALL RESULTS" || echo "No data")
EOF

cat test-summary.txt
```

---

## 🎓 Key Metrics Summary Template

After all tests, fill this in:

| Metric | Load | Spike | Stress | Soak |
|--------|------|-------|--------|------|
| **Max Users** | 100 | 500 | 600 | 75 |
| **Total Requests** | ___ | ___ | ___ | ___ |
| **Success Rate** | ___% | ___% | ___% | ___% |
| **p95 Latency** | ___ms | ___ms | ___ms | ___ms |
| **Throughput** | ___req/s | ___req/s | ___req/s | ___req/s |
| **Breaking Point** | N/A | N/A | ___users | N/A |
| **Memory Leak** | N/A | N/A | N/A | Yes/No |

---

## 🚀 Ready to Start?

**First, verify nginx-thrift is running with 2/2 containers:**

```bash
kubectl get pods -n cse239fall2025 | grep nginx-thrift
```

**If it shows `2/2 Running`** → **GO!** Start with Test 1 (Load Test)

**If it shows `1/1` or missing** → Stop, we need to fix nginx first

---

**Let me know the nginx-thrift status, and I'll guide you through all 4 tests!** 🎯
