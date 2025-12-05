# Complete Performance Analysis - What You CAN Do

**Direct answers to your questions:**

---

## ✅ Question 1: Average and Tail Latency Performance

### Answer: **YES, we can get this!** 

**How:**

1. **k6 automatically tracks latency** during stress tests
2. **After test completes**, parse k6 summary output
3. **Push to Pushgateway** and visualize in Grafana

### Steps:

```bash
# 1. Run stress test
cd scripts
kubectl apply -f k6-stress-job.yaml -n cse239fall2025

# 2. Wait for completion (watch logs)
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test

# 3. Extract latency metrics
cd ../scripts
bash push-k6-metrics.sh

# 4. Query in Grafana:
# k6_latency_avg_ms{job="k6-stress-test"}
# k6_latency_p95_ms{job="k6-stress-test"}
# k6_latency_p99_ms{job="k6-stress-test"}
```

### What You'll Get:

- ✅ **Average latency** - Mean response time
- ✅ **Median (p50) latency** - 50th percentile
- ✅ **p95 latency** - 95th percentile (tail latency)
- ✅ **p99 latency** - 99th percentile (tail latency)
- ✅ **Min/Max latency** - Best/worst case

---

## ✅ Question 2: CPU, Memory, and Request Rate Analysis

### Answer: **YES, with some limitations!**

### Request Rate: ✅ **Full Real-time Analysis**

**Already working!** Use these Grafana queries:

```promql
# Requests per second
rate(nginx_http_requests_total[1m])

# Requests per minute  
rate(nginx_http_requests_total[1m]) * 60

# Total requests
nginx_http_requests_total
```

**Create dashboard panels** and watch in real-time during stress test!

### CPU Usage: ✅ **Using kubectl top**

**Solution:** Use `kubectl top` command to get real CPU usage

**How:**
```bash
# Run the collection script
cd scripts
bash collect-resource-metrics.sh
```

**Grafana Queries:**
```promql
# CPU usage per pod (in cores)
pod_cpu_usage_cores{namespace="cse239fall2025"}

# Total CPU across all pods
sum(pod_cpu_usage_cores{namespace="cse239fall2025"})

# Top 5 CPU consuming pods
topk(5, pod_cpu_usage_cores{namespace="cse239fall2025"})
```

**Visualization:** Time series graph  
**Title:** "Pod CPU Usage (cores)"

### Memory Usage: ✅ **Using kubectl top**

**Solution:** Use `kubectl top` command to get real memory usage

**How:**
```bash
# Run the collection script
cd scripts
bash collect-resource-metrics.sh
```

**Grafana Queries:**
```promql
# Memory usage per pod (in bytes)
pod_memory_usage_bytes{namespace="cse239fall2025"}

# Total memory across all pods (in GB)
sum(pod_memory_usage_bytes{namespace="cse239fall2025"}) / 1024 / 1024 / 1024

# Top 5 memory consuming pods
topk(5, pod_memory_usage_bytes{namespace="cse239fall2025"})

# Memory per pod in Mi
pod_memory_usage_bytes{namespace="cse239fall2025"} / 1024 / 1024
```

**Visualization:** Time series graph  
**Title:** "Pod Memory Usage (MB)"

---

## Complete Dashboard Panels

### Panel 1: Request Rate (Real-time)
```promql
rate(nginx_http_requests_total[1m])
```
- **Type:** Time series
- **Unit:** req/sec
- **Title:** "Request Rate"

### Panel 2: CPU Usage (kubectl top)
```promql
sum(pod_cpu_usage_cores{namespace="cse239fall2025"})
```
- **Type:** Time series
- **Unit:** cores
- **Title:** "Total CPU Usage"

### Panel 3: Memory Usage (kubectl top)
```promql
sum(pod_memory_usage_bytes{namespace="cse239fall2025"}) / 1024 / 1024
```
- **Type:** Time series
- **Unit:** MB
- **Title:** "Total Memory Usage"

### Panel 4: Average Latency (After k6)
```promql
k6_latency_avg_ms{job="k6-stress-test"}
```
- **Type:** Stat panel
- **Unit:** ms
- **Title:** "Average Latency"

### Panel 5: P95 Latency (After k6)
```promql
k6_latency_p95_ms{job="k6-stress-test"}
```
- **Type:** Stat panel
- **Unit:** ms
- **Title:** "P95 Latency (Tail)"

### Panel 6: P99 Latency (After k6)
```promql
k6_latency_p99_ms{job="k6-stress-test"}
```
- **Type:** Stat panel
- **Unit:** ms
- **Title:** "P99 Latency (Tail)"

---

## Complete Workflow

### Step 1: Create Dashboard (Before Test)

1. Go to Grafana
2. Create new dashboard: "Stress Test Performance"
3. Add panels:
   - Request Rate (real-time)
   - CPU Load Proxy
   - Memory Load Proxy
4. Save dashboard

### Step 2: Run Stress Test

```bash
cd scripts
kubectl apply -f k6-stress-job.yaml -n cse239fall2025

# Watch Grafana dashboard - panels should update in real-time!
```

### Step 3: Collect All Metrics (After Test)

```bash
cd scripts

# Extract latency from k6 logs
bash push-k6-metrics.sh

# Collect CPU and memory using kubectl top
bash collect-resource-metrics.sh
```

### Step 4: Add Performance Panels

1. Go back to Grafana dashboard
2. Add panels:
   - Average Latency (k6)
   - P95 Latency (k6)
   - P99 Latency (k6)
   - Total CPU Usage (kubectl top)
   - Total Memory Usage (kubectl top)
3. Save dashboard

---

## Summary

### ✅ What You CAN Do:

| Requirement | Solution | Status |
|-------------|----------|--------|
| **Average Latency** | Parse k6 summary → Pushgateway | ✅ **YES** |
| **Tail Latency (p95/p99)** | Parse k6 summary → Pushgateway | ✅ **YES** |
| **Request Rate** | Nginx metrics (real-time) | ✅ **YES** |
| **CPU Usage** | Request rate as proxy | ⚠️ **Indirect** |
| **Memory Usage** | Connection count as proxy | ⚠️ **Indirect** |

### ❌ What You CANNOT Do (Nautilus Limitations):

- ❌ Real CPU metrics (kubelet API blocked)
- ❌ Real memory metrics (kubelet API blocked)

### ⚠️ Workaround:

- ✅ Use **request rate** = CPU load indicator
- ✅ Use **connections** = Memory load indicator
- ✅ These are **good proxies** for understanding load!

---

## Quick Start Commands

```bash
# 1. Run stress test
kubectl apply -f scripts/k6-stress-job.yaml -n cse239fall2025

# 2. Watch request rate in Grafana (real-time)
# Query: rate(nginx_http_requests_total[1m])

# 3. After test completes, collect all metrics
cd scripts
bash push-k6-metrics.sh           # Extracts latency from k6 logs
bash collect-resource-metrics.sh   # Collects CPU/memory via kubectl top

# 4. Query in Grafana:
# Latency:
#   k6_latency_avg_ms{job="k6-stress-test"}
#   k6_latency_p95_ms{job="k6-stress-test"}
#   k6_latency_p99_ms{job="k6-stress-test"}
# 
# CPU/Memory:
#   sum(pod_cpu_usage_cores{namespace="cse239fall2025"})
#   sum(pod_memory_usage_bytes{namespace="cse239fall2025"}) / 1024 / 1024
```

---

**See [YES-WE-CAN-DO-THIS.md](./YES-WE-CAN-DO-THIS.md) for quick summary!**

