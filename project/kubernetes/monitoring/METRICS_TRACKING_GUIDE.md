# Prometheus & Grafana Metrics Tracking Guide

This guide provides Prometheus queries (PromQL) for tracking the most important metrics for your autoscaling experiments. Each metric includes definitions, importance, normal/abnormal ranges, and how HPA/VPA affects it.

## Table of Contents

1. [CPU Metrics](#cpu-metrics)
2. [Memory Metrics](#memory-metrics)
3. [All Services Aggregated Metrics](#all-services-aggregated-metrics) ⭐ **NEW: Multi-Service Queries**
4. [Latency Metrics](#latency-metrics)
5. [Throughput Metrics](#throughput-metrics)
6. [Network Metrics](#network-metrics)
7. [Pod & Replica Metrics](#pod--replica-metrics)
8. [HPA Metrics](#hpa-metrics)
9. [VPA Metrics](#vpa-metrics)
10. [Error & Status Metrics](#error--status-metrics)

## Quick Reference: Key Metrics Locations

| Metric | Source | How to Access |
|--------|--------|---------------|
| **Latency p95/p99** | k6 JSON | `jq '.metrics.http_req_duration.values.p95' k6-results/*.json` |
| **Throughput** | k6 JSON | `jq '.metrics.http_reqs.values.rate' k6-results/*.json` |
| **CPU Usage (Single Service)** | Prometheus | `rate(container_cpu_usage_seconds_total{pod=~"user-service.*"}[5m])` |
| **CPU Usage (All Services - Stacked)** | Prometheus | ⭐ See [CPU Usage by Service (Stacked)](#cpu-usage-by-service-stacked-graph--primary-query) below |
| **Memory Usage (Single Service)** | Prometheus | `container_memory_usage_bytes{pod=~"user-service.*"}` |
| **Memory Usage (All Services - Stacked)** | Prometheus | See [Memory Usage by Service (Stacked)](#memory-usage-by-service-stacked-graph) below |
| **Pod Count (Single Service)** | Prometheus | `count(kube_pod_info{pod=~"user-service.*"})` |
| **Pod Count (All Services)** | Prometheus | See [All Services Aggregated Metrics](#all-services-aggregated-metrics) section |
| **Autoscaling Events** | kubectl logs | `kubectl get hpa -w` (run during test) |
| **Cost** | Manual calculation | Pod-hours × CPU/Memory × GCP pricing |

### ⭐ Quick Start: CPU Usage by Service (Stacked Graph)

**Copy this query into Grafana:**
```promql
sum by (service_name) (
  label_replace(
    sum(rate(container_cpu_usage_seconds_total{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD",
      container!=""
    }[5m])) by (pod) * 1000,
    "service_name",
    "$1",
    "pod",
    "(.*)-deployment-.*"
  )
)
```

**To enable stacking:**
1. Panel type: **Time series**
2. **Panel options** → **Graph styles** → **Stack**: Select **"Normal"**
3. **Fill opacity**: 0.3-0.5
4. **Y-axis**: Unit = Millicores (m), Min = 0

**Result:** Each service appears as a colored area in a stacked graph, showing total CPU usage per service over time.

---
## Experiment Configurations

### HPA Configurations

| Configuration | Type | Target Metric | Use Case |
|--------------|------|---------------|----------|
| `user-service-hpa-latency.yaml` | Latency-based | <400ms response time | Maintain <500ms target |
| `user-service-hpa-resource.yaml` | Resource-based | 70% CPU, 80% memory | Baseline comparison |

### VPA Configurations

| Configuration | CPU Range | Memory Range | Cost Profile |
|--------------|-----------|--------------|--------------|
| Conservative | 100m-500m | 128Mi-512Mi | Lower cost per pod |
| Moderate | 200m-1000m | 256Mi-1Gi | Balanced |
| Aggressive | 500m-2000m | 512Mi-2Gi | Higher cost per pod |
| CPU-Optimized | 500m-2000m | 256Mi-1Gi | High CPU, moderate memory |
| Memory-Optimized | 200m-1000m | 512Mi-2Gi | Moderate CPU, high memory |

## CPU Metrics

### 1. CPU Usage (Current Consumption)

**PromQL Query (Single Service - user-service):**
```promql
# CPU usage in millicores (m) for user-service pods
sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD", container!=""}[5m])) by (pod) * 1000

# Average CPU usage across all user-service pods
avg(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD", container!=""}[5m])) * 1000
```

**What it means:**
- Current CPU consumption by pods in millicores (1000m = 1 core)
- Measured over 5-minute windows

**Why it's important:**
- Primary metric for HPA scaling decisions
- High CPU = system is working hard, may need more pods
- Low CPU = system is idle, may be over-provisioned

**Normal ranges:**
- **Idle**: 0-50m per pod
- **Normal load**: 200-500m per pod
- **High load**: 500-1000m per pod
- **Critical**: >1000m (hitting CPU limit)

**Abnormal ranges:**
- **<10m for extended periods**: System may be idle, consider scale-down
- **>800m consistently**: Approaching CPU limit, may need scaling or VPA adjustment
- **>1000m**: CPU throttling likely occurring

**How HPA affects it:**
- HPA scales up when average CPU > target (e.g., 70%)
- More pods = lower average CPU per pod (load distribution)
- HPA scales down when average CPU < target

**How VPA affects it:**
- VPA increases CPU requests/limits when usage is consistently high
- Higher CPU limits = pods can handle more load before throttling
- Lower CPU limits = pods may throttle, causing latency spikes

---

### 2. CPU Requests vs Usage

**PromQL Query:**
```promql
# CPU usage as percentage of request
(sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod) * 1000) 
/ 
(sum(container_spec_cpu_quota{pod=~"user-service-deployment-.*", container!="POD"} / container_spec_cpu_period{pod=~"user-service-deployment-.*", container!="POD"}) by (pod)) 
* 100

# Simpler version (if available)
sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*"}[5m])) by (pod) 
/ 
sum(container_spec_cpu_request{pod=~"user-service-deployment-.*"}) by (pod) 
* 100
```

**What it means:**
- CPU usage as a percentage of requested CPU
- 100% = using all requested CPU, may need more
- >100% = exceeding request (using burst capacity)

**Why it's important:**
- Shows if CPU requests are appropriately sized
- HPA uses this metric for scaling decisions
- >100% consistently = VPA should increase requests

**Normal ranges:**
- **50-80%**: Good utilization, headroom for spikes
- **80-100%**: High utilization, monitor for scaling needs
- **>100%**: Exceeding request, using burst capacity

**Abnormal ranges:**
- **<30% consistently**: Over-provisioned, VPA should reduce requests
- **>100% consistently**: Under-provisioned, VPA should increase requests

**How HPA affects it:**
- HPA target (e.g., 70%) is based on this percentage
- When >70%, HPA scales up to bring it back to ~70%

**How VPA affects it:**
- VPA adjusts CPU requests to keep this around 80-90%
- Higher requests = lower percentage (more headroom)
- Lower requests = higher percentage (less headroom)

---

### 3. CPU Throttling

**PromQL Query:**
```promql
# CPU throttling rate (how often CPU is being throttled)
sum(rate(container_cpu_cfs_throttled_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod)

# Throttling percentage
sum(rate(container_cpu_cfs_throttled_seconds_total{pod=~"user-service-deployment-.*"}[5m])) by (pod)
/
sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*"}[5m])) by (pod)
* 100
```

**What it means:**
- How often pods are being throttled (CPU limit exceeded)
- Throttling = CPU requests are delayed, causing latency

**Why it's important:**
- Indicates CPU limits are too low
- Throttling causes latency spikes and poor performance
- Should be 0% under normal conditions

**Normal ranges:**
- **0%**: No throttling (ideal)
- **<1%**: Minimal throttling (acceptable)
- **>1%**: Significant throttling (problem)

**Abnormal ranges:**
- **>5%**: Critical - pods are severely CPU constrained
- **>10%**: System is overloaded, immediate action needed

**How HPA affects it:**
- More pods = less CPU per pod = less throttling
- HPA scaling up can reduce throttling by distributing load

**How VPA affects it:**
- VPA should increase CPU limits when throttling is detected
- Higher limits = less throttling = better performance

---

## Memory Metrics

### 4. Memory Usage

**PromQL Query (Single Service - user-service):**
```promql
# Memory usage in bytes for user-service pods
sum(container_memory_working_set_bytes{pod=~"user-service-deployment-.*", container!="POD", container!=""}) by (pod)

# Memory usage in MiB
sum(container_memory_working_set_bytes{pod=~"user-service-deployment-.*", container!="POD"}) by (pod) / 1024 / 1024

# Average memory usage across pods
avg(container_memory_working_set_bytes{pod=~"user-service-deployment-.*", container!="POD"}) / 1024 / 1024
```

**PromQL Query (All Services - Multi-Service Graph):**
```promql
# Total memory usage per service (aggregated across all pods per service)
sum by (service) (
  label_replace(
    sum(container_memory_working_set_bytes{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD",
      container!=""
    }) by (pod),
    "service",
    "$1",
    "pod",
    "(.*)-deployment-.*"
  )
) / 1024 / 1024

# Average memory usage per service (across all pods of each service)
avg by (service) (
  label_replace(
    sum(container_memory_working_set_bytes{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD",
      container!=""
    }) by (pod) / 1024 / 1024,
    "service",
    "$1",
    "pod",
    "(.*)-deployment-.*"
  )
)

# Memory usage per pod (all services, one line per pod)
sum(container_memory_working_set_bytes{
  pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
  container!="POD",
  container!=""
}) by (pod) / 1024 / 1024
```

**What it means:**
- Current memory consumption by pods (working set = actively used memory)
- Measured in bytes (divide by 1024² for MiB)

**Why it's important:**
- Secondary metric for HPA scaling decisions
- High memory = may need more pods or VPA adjustment
- Approaching limit = risk of OOM (Out of Memory) kills

**Normal ranges:**
- **Idle**: 50-100 MiB per pod
- **Normal load**: 100-200 MiB per pod
- **High load**: 200-400 MiB per pod
- **Critical**: >80% of limit

**Abnormal ranges:**
- **<50 MiB consistently**: May be over-provisioned
- **>90% of limit**: Risk of OOM kill
- **Rapid growth**: Memory leak possible

**How HPA affects it:**
- HPA scales up when average memory > target (e.g., 80%)
- More pods = lower average memory per pod

**How VPA affects it:**
- VPA increases memory requests/limits when usage is consistently high
- Higher limits = more headroom, less OOM risk
- Lower limits = less headroom, more OOM risk

---

### 5. Memory Requests vs Usage

**PromQL Query:**
```promql
# Memory usage as percentage of request
sum(container_memory_working_set_bytes{pod=~"user-service-deployment-.*", container!="POD"}) by (pod)
/
sum(container_spec_memory_request_bytes{pod=~"user-service-deployment-.*", container!="POD"}) by (pod)
* 100

# Average across all pods
avg(
  sum(container_memory_working_set_bytes{pod=~"user-service-deployment-.*", container!="POD"}) by (pod)
  /
  sum(container_spec_memory_request_bytes{pod=~"user-service-deployment-.*", container!="POD"}) by (pod)
  * 100
)
```

**What it means:**
- Memory usage as percentage of requested memory
- 100% = using all requested memory
- >100% = exceeding request (using burst capacity)

**Why it's important:**
- Shows if memory requests are appropriately sized
- HPA uses this for scaling decisions
- >100% consistently = VPA should increase requests

**Normal ranges:**
- **60-85%**: Good utilization
- **85-100%**: High utilization, monitor closely
- **>100%**: Exceeding request

**Abnormal ranges:**
- **<40% consistently**: Over-provisioned, VPA should reduce
- **>100% consistently**: Under-provisioned, VPA should increase

**How HPA affects it:**
- HPA target (e.g., 80%) is based on this percentage
- When >80%, HPA scales up

**How VPA affects it:**
- VPA adjusts memory requests to keep this around 80-90%

---

### 6. OOM Kills (Out of Memory)

**PromQL Query:**
```promql
# Count of OOM kills
sum(increase(container_oom_kills_total{pod=~"user-service-deployment-.*"}[5m])) by (pod)

# OOM kill rate
rate(container_oom_kills_total{pod=~"user-service-deployment-.*"}[5m])
```

**What it means:**
- Number of times pods were killed due to exceeding memory limit
- Each kill = pod restart = service interruption

**Why it's important:**
- Indicates memory limits are too low
- OOM kills cause downtime and poor user experience
- Should be 0 under normal conditions

**Normal ranges:**
- **0**: No OOM kills (ideal)

**Abnormal ranges:**
- **>0**: Critical - memory limits need immediate adjustment
- **>1 per hour**: System is severely misconfigured

**How HPA affects it:**
- More pods = less memory per pod = fewer OOM kills
- HPA scaling up can help, but VPA is better solution

**How VPA affects it:**
- VPA should increase memory limits when OOM kills occur
- Primary solution for OOM kills

---

## All Services Aggregated Metrics

### Quick Reference: All Services in One Graph (Stacked)

These queries aggregate metrics across **all microservices** so you can see all services in a single Grafana graph. Each service will appear as a separate stacked area.

**Service Pattern Matching:**
- Matches: `*-service-deployment-*`, `nginx-thrift-deployment-*`, `write-home-timeline-service-deployment-*`
- Covers all 12 microservices + nginx-thrift + write-home-timeline

### CPU Usage by Service (Stacked Graph) ⭐ **PRIMARY QUERY**

**PromQL Query (Groups by Service Name - Ready for Stacking):**
```promql
# CPU usage per service (sum across all pods of each service)
# Each service = one colored area in the stacked graph
sum by (service_name) (
  label_replace(
    sum(rate(container_cpu_usage_seconds_total{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD",
      container!=""
    }[5m])) by (pod) * 1000,
    "service_name",
    "$1",
    "pod",
    "(.*)-deployment-.*"
  )
)
```

**What this query does:**
1. Matches all service pods (12 microservices + nginx-thrift + write-home-timeline)
2. Calculates CPU usage per pod in millicores
3. Uses `label_replace` to extract service name from pod name
   - Example: `user-service-deployment-abc123` → `user-service`
4. Groups by `service_name` and sums CPU across all pods of each service
5. Result: One time series per service (not per pod)

**Grafana Setup for Stacked Visualization:**

1. **Add the Query:**
   - Copy the query above into Grafana
   - Panel type: **Time series**

2. **Enable Stacking:**
   - Go to **Panel options** (right sidebar)
   - Scroll to **"Graph styles"** section
   - Find **"Stack"** dropdown
   - Select **"Normal"** (for absolute values) or **"100%"** (for percentage view)
   - **Fill opacity**: Set to 0.3-0.5 (adjust for visibility)
   - **Gradient mode**: Optional - "Opacity" for better visual distinction

3. **Panel Settings:**
   - **Title**: "CPU Usage by Service (Stacked)"
   - **Y-axis**: 
     - **Unit**: Millicores (m)
     - **Min**: 0 (important for proper stacking)
     - **Max**: Auto or set specific value
   - **Legend**: 
     - **Show legend**: Yes
     - **Placement**: Bottom or Right

**What it shows:**
- **Total CPU per service**: Sum of CPU across all pods of each service
- Each service appears as a colored area in the stack
- Stacked total shows overall CPU usage across all services
- Easy to see which services consume the most CPU at any time
- Similar to your example graph, but grouped by service name instead of individual pods

**Example Output:**
- `compose-post-service`: ~50m CPU (sum of all compose-post pods)
- `home-timeline-service`: ~40m CPU (sum of all home-timeline pods)
- `nginx-thrift`: ~30m CPU
- `post-storage-service`: ~60m CPU
- etc.

**Alternative Query (If label_replace doesn't work):**
```promql
# CPU usage per pod (all services)
# Then use Grafana Transform to group by service name
sum(rate(container_cpu_usage_seconds_total{
  pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
  container!="POD",
  container!=""
}[5m])) by (pod) * 1000
```

**Then in Grafana:**
1. Add **Transform** → **"Add field from calculation"**
2. Or use **"Rename by regex"** transform:
   - Match: `(.*)-deployment-.*`
   - Replace: `$1`
3. Add **"Group by"** transform:
   - Group by: The new service name field
   - Operation: Sum

### Memory Usage by Service (Stacked Graph)

**PromQL Query:**
```promql
# Memory usage per service (sum across all pods of each service)
sum by (service_name) (
  label_replace(
    sum(container_memory_working_set_bytes{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD",
      container!=""
    }) by (pod),
    "service_name",
    "$1",
    "pod",
    "(.*)-deployment-.*"
  )
) / 1024 / 1024
```

**Alternative Query (If label_replace doesn't work):**
```promql
# Memory usage per pod (all services)
# Use Grafana Transform to group by service name
sum(container_memory_working_set_bytes{
  pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
  container!="POD",
  container!=""
}) by (pod) / 1024 / 1024
```

**Grafana Setup:**
- Same stacking setup as CPU usage above
- **Stack**: Normal
- **Y-axis**: MiB (Mebibytes)

**What it shows:**
- **Total memory per service**: Sum of memory across all pods of each service
- Each service appears as a colored area in the stack
- Stacked total shows overall memory usage across all services

### CPU Usage Percentage by Service (Stacked)

**PromQL Query:**
```promql
# CPU usage as percentage of request (per service)
sum by (service_name) (
  label_replace(
    (sum(rate(container_cpu_usage_seconds_total{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD"
    }[5m])) by (pod) * 1000)
    /
    (sum(container_spec_cpu_request{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD"
    }) by (pod)),
    "service_name",
    "$1",
    "pod",
    "(.*)-deployment-.*"
  )
) * 100
```

**Grafana Setup:**
- **Stack**: 100% (shows percentage distribution)
- **Y-axis**: Percentage (0-100%)

**What it shows:**
- CPU usage as percentage of requested CPU for each service
- Useful for identifying which services are approaching HPA thresholds
- Stacked to 100% shows relative CPU usage distribution

### Memory Usage Percentage by Service (Stacked)

**PromQL Query:**
```promql
# Memory usage as percentage of request (per service)
sum by (service_name) (
  label_replace(
    (sum(container_memory_working_set_bytes{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD"
    }) by (pod))
    /
    (sum(container_spec_memory_request_bytes{
      pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
      container!="POD"
    }) by (pod)),
    "service_name",
    "$1",
    "pod",
    "(.*)-deployment-.*"
  )
) * 100
```

**Grafana Setup:**
- **Stack**: 100% (shows percentage distribution)
- **Y-axis**: Percentage (0-100%)

**What it shows:**
- Memory usage as percentage of requested memory for each service
- Useful for identifying which services are approaching HPA thresholds

### Alternative: Using Grafana Transforms (If label_replace Doesn't Work)

If `label_replace` doesn't work in your Prometheus setup, use per-pod queries and let Grafana group by service:

**Step 1: Add Per-Pod Query**
```promql
# CPU usage per pod (all services)
sum(rate(container_cpu_usage_seconds_total{
  pod=~".*-service-deployment-.*|nginx-thrift-deployment-.*|write-home-timeline-service-deployment-.*",
  container!="POD",
  container!=""
}[5m])) by (pod) * 1000
```

**Step 2: Add Grafana Transforms**

1. **Add "Add field from calculation"** or **"Organize fields"** transform
2. **Add "Group by"** transform:
   - **Field**: `pod`
   - **Operation**: Sum
   - **Alias**: Use regex to extract service name: `$1` from pattern `(.*)-deployment-.*`

3. **Better approach - Use "Add field from calculation"** with regex:
   - Add transform: **"Add field from calculation"**
   - Mode: **"Binary operation"**
   - Or use **"Rename by regex"** transform:
     - Match: `(.*)-deployment-.*`
     - Replace: `$1`
   - Then **"Group by"** transform grouping by the new service name field

**Step 3: Enable Stacking**
- Go to **Panel options** → **Visualization** → **Time series**
- **Stack**: Normal (or 100% for percentage)
- **Fill opacity**: 0.3-0.5

### Detailed Grafana Stacking Setup

**To create a stacked graph like your example:**

1. **Panel Settings:**
   - **Visualization**: Time series
   - **Panel title**: "CPU Usage by Service (Stacked)"

2. **Graph Styles:**
   - **Stack**: **Normal** (for absolute values) or **100%** (for percentage)
   - **Fill opacity**: 0.3-0.5 (adjust for visibility)
   - **Line width**: 1-2 (optional, for area borders)
   - **Gradient mode**: None or Opacity (for better visual distinction)

3. **Legend:**
   - **Show legend**: Yes
   - **Legend placement**: Bottom or Right
   - **Legend values**: Optional (Current, Min, Max, etc.)

4. **Y-Axis:**
   - **Unit**: Millicores (m) for CPU, MiB for Memory
   - **Min**: 0 (for proper stacking)
   - **Max**: Auto or set specific value

5. **X-Axis:**
   - **Time range**: Auto or your test duration
   - **Show**: Yes

### Tips for Using All-Services Queries

1. **Service Name Extraction:**
   - The `label_replace` function extracts service name from pod name
   - Pattern: `(.*)-deployment-.*` captures service name
   - Example: `user-service-deployment-abc123` → `user-service`
   - **Label name**: Use `service_name` (not `service`) to avoid conflicts

2. **Stacking Options:**
   - **Normal**: Shows absolute values, total = sum of all services
   - **100%**: Shows percentage distribution, total always = 100%
   - **None**: Shows overlapping lines (not stacked)

3. **Filtering Specific Services:**
   - Add filter to query: `service_name=~"user-service|compose-post-service"`
   - Or filter by pod name pattern: `pod=~"user-service-deployment-.*|compose-post-service-deployment-.*"`

4. **Troubleshooting:**
   - If services don't appear: Check that pod names match the regex pattern
   - If stacking doesn't work: Ensure all series have the same time range
   - If colors overlap: Adjust fill opacity or use different visualization mode

---

## Latency Metrics

### 7. Request Latency (p50, p95, p99)

**⚠️ IMPORTANT: DeathStarBench services use Thrift RPC, not HTTP, so `http_request_duration_seconds` metrics are NOT available.**

**Primary Source: k6 Test Results (External Monitoring)**

Latency metrics should be obtained from k6 test results, not Prometheus:

```bash
# Extract latency metrics from k6 JSON results
jq '.metrics.http_req_duration.values.p50' k6-results/*.json
jq '.metrics.http_req_duration.values.p95' k6-results/*.json
jq '.metrics.http_req_duration.values.p99' k6-results/*.json

# Or from summary files
grep "p(95)" k6-results/*_summary.txt
grep "p(99)" k6-results/*_summary.txt
```

**Alternative: Use CPU/Resource Metrics as Latency Indicators**

While not direct latency measurements, these metrics correlate with performance:

```promql
# CPU usage per request (proxy for processing time)
# Higher CPU usage = more processing = potentially higher latency
sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod) * 1000

# CPU throttling (indicates resource constraints = higher latency)
sum(rate(container_cpu_cfs_throttled_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod)

# Memory pressure (can cause GC pauses = latency spikes)
sum(container_memory_working_set_bytes{pod=~"user-service-deployment-.*", container!="POD"}) by (pod)
/
sum(container_spec_memory_limit_bytes{pod=~"user-service-deployment-.*", container!="POD"}) by (pod)
* 100

# If HTTP metrics were available (for reference):
# histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="user-service"}[5m])) by (le, pod))
```

**What it means:**
- **k6 results**: Actual end-to-end latency from load tests (most accurate)
- **CPU usage**: High CPU = pods working hard = may indicate latency issues
- **CPU throttling**: Throttling = requests delayed = higher latency
- **Memory pressure**: High memory = GC pauses = latency spikes

**Why it's important:**
- Primary metric for latency-based HPA (from k6 or external monitoring)
- High latency = poor user experience
- Resource constraints (CPU throttling, memory pressure) cause latency

**Normal ranges:**
- **k6 p50**: < 100ms
- **k6 p95**: < 500ms
- **k6 p99**: < 1000ms
- **CPU usage**: < 70% of request (HPA target)
- **CPU throttling**: 0% (no throttling)
- **Memory pressure**: < 80% of limit

**Abnormal ranges:**
- **k6 p95 > 1000ms**: System is overloaded
- **k6 p99 > 5000ms**: Critical performance issue
- **CPU throttling > 0%**: Resource constraints causing latency
- **Memory > 90%**: Risk of GC pauses and latency spikes

**How HPA affects it:**
- More pods = lower per-pod CPU = lower latency (load distribution)
- HPA scaling up reduces latency by reducing per-pod load
- Latency-based HPA uses k6 results or external monitoring

**How VPA affects it:**
- Higher CPU/memory = pods process requests faster = lower latency
- VPA optimizing resources improves latency
- Insufficient resources = CPU throttling = higher latency

---

### 8. Request Latency by Endpoint

**⚠️ IMPORTANT: DeathStarBench services use Thrift RPC, not HTTP, so endpoint-level latency metrics are NOT available.**

**Primary Source: k6 Test Results with Endpoint Breakdown**

Use k6 test results to analyze latency by endpoint:

```bash
# Extract latency by endpoint from k6 JSON
jq '.metrics | to_entries | map(select(.key | contains("duration"))) | .[] | {name: .key, p95: .value.values.p95, p99: .value.values.p99}' k6-results/*.json

# Or analyze k6 summary by endpoint tag
grep -A 5 "ComposePost\|ReadHomeTimeline\|RegisterUser" k6-results/*_summary.txt
```

**Alternative: Use Resource Metrics to Identify Bottlenecks**

While not endpoint-specific, you can identify which services are under stress:

```promql
# CPU usage by service (identifies which services are overloaded)
sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod) * 1000
sum(rate(container_cpu_usage_seconds_total{pod=~"compose-post-service-deployment-.*", container!="POD"}[5m])) by (pod) * 1000
sum(rate(container_cpu_usage_seconds_total{pod=~"social-graph-service-deployment-.*", container!="POD"}[5m])) by (pod) * 1000

# CPU throttling by service (indicates which services are resource-constrained)
sum(rate(container_cpu_cfs_throttled_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod)
```

**What it means:**
- **k6 endpoint breakdown**: Actual latency per endpoint from load tests
- **Service-level CPU**: High CPU on a specific service = that service may be a bottleneck
- **Service-level throttling**: Throttling on a service = that service needs more resources

**Why it's important:**
- Some endpoints/services may be slower than others
- Helps identify bottlenecks at the service level
- Useful for optimizing specific services or scaling decisions

**Normal ranges:**
- Same as overall latency (from k6)
- Some services may naturally use more CPU (e.g., database-heavy operations)

**Abnormal ranges:**
- Same as overall latency
- Services with high CPU/throttling may benefit more from scaling or VPA adjustment

---

## Throughput Metrics

### 9. Requests Per Second (RPS)

**⚠️ IMPORTANT: DeathStarBench services use Thrift RPC, not HTTP, so `http_requests_total` metrics are NOT available.**

**Alternative: Use CPU/Network metrics as a proxy for request rate:**

**PromQL Query:**
```promql
# Estimate RPS from CPU usage (proxy metric)
# Higher CPU usage = more requests being processed
sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod) * 100

# Network bytes received per second (proxy for request rate)
sum(rate(container_network_receive_bytes_total{pod=~"user-service-deployment-.*"}[5m])) by (pod) / 1024

# Network bytes transmitted per second
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[5m])) by (pod) / 1024

# If HTTP metrics were available (for reference):
# sum(rate(http_requests_total{service="user-service"}[5m])) by (service)
# sum(rate(http_requests_total{service="user-service"}[5m])) by (pod)
```

**What it means:**
- **CPU-based proxy**: CPU usage correlates with request processing rate
- **Network-based proxy**: Network traffic indicates request volume
- **Note**: These are approximations, not exact request counts

**Why it's important:**
- Shows relative load on the system
- Higher CPU/network = more traffic = may need scaling
- CPU per pod shows load distribution

**Normal ranges:**
- **Idle**: CPU < 50m per pod, Network < 1 KB/s
- **Normal load**: CPU 200-500m per pod, Network 10-100 KB/s
- **High load**: CPU 500-1000m per pod, Network 100-1000 KB/s
- **Per pod**: Monitor CPU usage as primary indicator

**Abnormal ranges:**
- **CPU per pod > 800m consistently**: Pods are overloaded, need scaling
- **CPU = 0**: No traffic (check if service is down)

**How HPA affects it:**
- More pods = lower average CPU per pod (load distribution)
- HPA scales up when CPU increases (direct metric)
- Network traffic increases with more pods

**How VPA affects it:**
- Higher CPU/memory = pods can handle more requests
- VPA optimizing resources increases per-pod capacity

---

### 10. Requests Per Second Per Pod

**⚠️ IMPORTANT: DeathStarBench services use Thrift RPC, not HTTP, so `http_requests_total` metrics are NOT available.**

**Alternative: Use CPU/Network metrics as a proxy:**

**PromQL Query:**
```promql
# Average CPU usage per pod (proxy for average RPS per pod)
avg(sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod)) * 1000

# CPU usage per pod (detailed - shows load distribution)
sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[5m])) by (pod) * 1000

# Network receive rate per pod (proxy for request rate)
sum(rate(container_network_receive_bytes_total{pod=~"user-service-deployment-.*"}[5m])) by (pod) / 1024

# If HTTP metrics were available (for reference):
# avg(sum(rate(http_requests_total{service="user-service"}[5m])) by (pod))
# sum(rate(http_requests_total{service="user-service"}[5m])) by (pod)
```

**What it means:**
- **CPU per pod**: Shows relative request processing rate per pod
- **Network per pod**: Shows data volume per pod (proxy for request volume)
- Shows load distribution across pods

**Why it's important:**
- Uneven distribution = some pods overloaded
- High per-pod RPS = may need more pods
- Low per-pod RPS = may have too many pods

**Normal ranges:**
- **10-50 RPS per pod**: Good distribution
- **50-100 RPS per pod**: High but acceptable
- **>100 RPS per pod**: Pods may be overloaded

**Abnormal ranges:**
- **>150 RPS per pod**: Critical overload
- **<5 RPS per pod with many pods**: Over-provisioned

**How HPA affects it:**
- HPA scaling up reduces RPS per pod (load distribution)
- Target: Keep RPS per pod in manageable range

**How VPA affects it:**
- VPA optimizing resources allows pods to handle more RPS
- Higher resources = higher per-pod RPS capacity

---

## Network Metrics

### 11. Network Bytes Transmitted

**PromQL Query:**
```promql
# Bytes transmitted per second (outgoing)
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[5m])) by (pod)

# Total bytes transmitted
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[5m]))
```

**What it means:**
- Amount of data sent by pods over the network
- Measured in bytes per second

**Why it's important:**
- High network usage = high traffic = may need scaling
- Network bandwidth can be a bottleneck
- Useful for capacity planning

**Normal ranges:**
- **Idle**: <1 MB/s
- **Normal load**: 1-10 MB/s per pod
- **High load**: 10-50 MB/s per pod

**Abnormal ranges:**
- **>100 MB/s per pod**: Very high network usage, investigate
- **Sudden spikes**: May indicate DDoS or traffic surge

**How HPA affects it:**
- More pods = more total network capacity
- Network usage per pod decreases with more pods

**How VPA affects it:**
- VPA doesn't directly affect network (no network requests/limits)
- But higher CPU = faster request processing = more network throughput

---

### 12. Network Bytes Received

**PromQL Query:**
```promql
# Bytes received per second (incoming)
sum(rate(container_network_receive_bytes_total{pod=~"user-service-deployment-.*"}[5m])) by (pod)

# Total bytes received
sum(rate(container_network_receive_bytes_total{pod=~"user-service-deployment-.*"}[5m]))
```

**What it means:**
- Amount of data received by pods over the network
- Usually similar to transmitted (request/response)

**Why it's important:**
- Shows incoming traffic volume
- High receive = many requests = may need scaling

**Normal ranges:**
- Similar to transmitted bytes
- **Idle**: <1 MB/s
- **Normal load**: 1-10 MB/s per pod

**Abnormal ranges:**
- **>100 MB/s per pod**: Very high, investigate
- **Large discrepancy with transmitted**: May indicate data processing issues

**How HPA/VPA affects it:**
- Same as transmitted bytes

---

### 13. Network Connections

**PromQL Query:**
```promql
# Active network connections
sum(container_network_tcp_connections{pod=~"user-service-deployment-.*", state="established"}) by (pod)

# Connection rate
sum(rate(container_network_tcp_connections_total{pod=~"user-service-deployment-.*"}[5m])) by (pod)
```

**What it means:**
- Number of active TCP connections to/from pods
- Established = active connections

**Why it's important:**
- High connection count = high load
- Connection limits can be a bottleneck
- Useful for understanding connection pooling

**Normal ranges:**
- **10-100 connections per pod**: Normal
- **100-500 connections per pod**: High but acceptable
- **>500 connections per pod**: Very high

**Abnormal ranges:**
- **>1000 connections per pod**: Critical, may hit connection limits
- **Rapid growth**: May indicate connection leak

**How HPA affects it:**
- More pods = connections distributed = lower per-pod connections

**How VPA affects it:**
- VPA doesn't directly affect network connections
- But better resources = faster connection handling

---

## Pod & Replica Metrics

### 14. Pod Replica Count

**PromQL Query:**
```promql
# Current number of user-service pods
count(kube_pod_info{pod=~"user-service-deployment-.*"})

# Pods by status
count(kube_pod_status_phase{pod=~"user-service-deployment-.*", phase="Running"})
count(kube_pod_status_phase{pod=~"user-service-deployment-.*", phase="Pending"})
count(kube_pod_status_phase{pod=~"user-service-deployment-.*", phase="Failed"})
```

**What it means:**
- Current number of pod replicas running
- Shows HPA scaling decisions in action

**Why it's important:**
- Direct indicator of HPA behavior
- More pods = higher cost but better performance
- Fewer pods = lower cost but risk of overload

**Normal ranges:**
- **Min replicas (e.g., 2)**: When idle
- **2-10 pods**: During normal to high load
- **Max replicas (e.g., 10)**: During peak load

**Abnormal ranges:**
- **Hitting max replicas consistently**: May need to increase maxReplicas
- **Staying at min replicas during load**: HPA may not be working
- **Rapid oscillation**: HPA behavior may need tuning

**How HPA affects it:**
- HPA directly controls this metric
- Scales up/down based on metrics

**How VPA affects it:**
- VPA doesn't directly control replica count
- But optimized resources = fewer pods needed for same load

---

### 15. Pod Ready Status

**PromQL Query:**
```promql
# Pods that are ready (using kube_pod_container_status_ready)
# Note: Filter by namespace and pod name pattern
sum(kube_pod_container_status_ready{namespace="default", pod=~"user-service-deployment-.*", container!="POD"})

# Pods that are not ready
count(kube_pod_container_status_ready{namespace="default", pod=~"user-service-deployment-.*", container!="POD"}) 
- sum(kube_pod_container_status_ready{namespace="default", pod=~"user-service-deployment-.*", container!="POD"})

# Ready percentage
(sum(kube_pod_container_status_ready{namespace="default", pod=~"user-service-deployment-.*", container!="POD"}) 
 / count(kube_pod_container_status_ready{namespace="default", pod=~"user-service-deployment-.*", container!="POD"})) * 100

# Alternative: Use pod phase (Running = ready)
count(kube_pod_status_phase{namespace="default", pod=~"user-service-deployment-.*", phase="Running"})

# Alternative: Use deployment replica metrics (if available)
# kube_deployment_status_replicas_available{namespace="default", deployment="user-service-deployment"}
```

**What it means:**
- Whether pods are ready to serve traffic
- Ready = pod is healthy and can accept requests

**Why it's important:**
- Not-ready pods don't serve traffic
- Reduces effective capacity
- Indicates health issues

**Normal ranges:**
- **100% ready**: All pods healthy (ideal)
- **>90% ready**: Acceptable
- **<90% ready**: Problem

**Abnormal ranges:**
- **<50% ready**: Critical, many pods unhealthy
- **0% ready**: Service is down

**How HPA affects it:**
- HPA counts only ready pods
- Unhealthy pods don't count toward capacity

**How VPA affects it:**
- VPA doesn't directly affect readiness
- But resource constraints can cause pods to be not ready

---

## HPA Metrics

### 16. HPA Desired Replicas

**PromQL Query:**
```promql
# ⚠️ NOTE: kube_horizontalpodautoscaler_status_* metrics are NOT available in GKE-managed kube-state-metrics
# Alternative: Use pod count metrics to track scaling

# Count of running pods (proxy for current replicas)
count(kube_pod_status_phase{namespace="default", pod=~"user-service-deployment-.*", phase="Running"})

# Count of ready pods
sum(kube_pod_container_status_ready{namespace="default", pod=~"user-service-deployment-.*", container!="POD"})

# If deployment metrics are available:
# kube_deployment_spec_replicas{namespace="default", deployment="user-service-deployment"}
# kube_deployment_status_replicas_available{namespace="default", deployment="user-service-deployment"}

# To get HPA desired replicas, use kubectl instead:
# kubectl get hpa user-service-hpa -n default -o jsonpath='{.status.desiredReplicas}'
```

**What it means:**
- Desired = what HPA wants (based on metrics)
- Current = what actually exists
- Difference = how much scaling is needed

**Why it's important:**
- Shows HPA scaling decisions
- Large difference = HPA wants to scale but can't (hitting limits?)
- Zero difference = HPA is satisfied

**Normal ranges:**
- **Difference = 0**: HPA is satisfied
- **Difference = 1-2**: Normal scaling in progress
- **Difference > 3**: Significant scaling needed

**Abnormal ranges:**
- **Large difference for extended time**: HPA may be hitting min/max limits
- **Rapid oscillation**: HPA behavior needs tuning

**How HPA affects it:**
- This IS the HPA metric
- Shows HPA's scaling intentions

**How VPA affects it:**
- VPA doesn't directly affect this
- But optimized resources = HPA may want fewer pods

---

### 17. HPA Metric Values

**PromQL Query:**
```promql
# CPU metric value HPA is seeing
kube_horizontalpodautoscaler_status_condition{horizontalpodautoscaler="user-service-hpa", condition="AbleToScale"}

# HPA scaling events (if available)
increase(kube_horizontalpodautoscaler_status_current_replicas{horizontalpodautoscaler="user-service-hpa"}[5m])
```

**What it means:**
- The actual metric values HPA is using for decisions
- Shows why HPA wants to scale

**Why it's important:**
- Understands HPA decision-making
- Debugs why HPA isn't scaling as expected

**Normal ranges:**
- Varies by HPA target settings
- CPU: Should be around target (e.g., 70%)
- Memory: Should be around target (e.g., 80%)

**Abnormal ranges:**
- **Metrics not available**: HPA can't make decisions
- **Metrics way above/below target**: HPA should be scaling

**How HPA affects it:**
- This is what HPA uses for decisions

**How VPA affects it:**
- VPA optimizing resources changes these metric values
- Better resources = lower utilization percentages

---

## VPA Metrics

### 18. VPA Recommendations

**PromQL Query:**
```promql
# VPA CPU recommendation
vpa_recommendation{resource="cpu", vpa="user-service-vpa"}

# VPA Memory recommendation
vpa_recommendation{resource="memory", vpa="user-service-vpa"}

# VPA recommendation vs current request
vpa_recommendation{resource="cpu", vpa="user-service-vpa"}
/
kube_pod_container_resource_requests{resource="cpu", pod=~"user-service-deployment-.*"}
* 100
```

**What it means:**
- What VPA recommends for CPU/memory requests
- Shows if current requests are optimal

**Why it's important:**
- Shows VPA's analysis
- Large difference = current requests are suboptimal
- VPA should adjust requests to match recommendations

**Normal ranges:**
- **Recommendation ≈ Current**: Requests are well-sized
- **Recommendation > Current**: VPA wants to increase (under-provisioned)
- **Recommendation < Current**: VPA wants to decrease (over-provisioned)

**Abnormal ranges:**
- **>200% difference**: Significant misconfiguration
- **Rapid changes**: Workload is highly variable

**How HPA affects it:**
- HPA doesn't directly affect VPA recommendations
- But HPA scaling changes per-pod load = changes VPA recommendations

**How VPA affects it:**
- This IS the VPA metric
- VPA updates recommendations based on historical usage

---

### 19. VPA Update Status

**PromQL Query:**
```promql
# VPA update mode
vpa_status_update_mode{vpa="user-service-vpa"}

# VPA target recommendation
vpa_target_recommendation{resource="cpu", vpa="user-service-vpa"}
vpa_target_recommendation{resource="memory", vpa="user-service-vpa"}
```

**What it means:**
- Whether VPA is in "Off", "Initial", "Auto", or "Recreate" mode
- Target = what VPA is targeting

**Why it's important:**
- Shows VPA operational status
- "Auto" mode = VPA is actively managing resources
- "Off" = VPA is only providing recommendations

**Normal ranges:**
- **Auto mode**: VPA is actively managing (for experiments)
- **Initial mode**: VPA is learning (first few hours)

**Abnormal ranges:**
- **Off mode**: VPA not applying changes (may be intentional)
- **Recreate mode**: VPA is recreating pods (may cause brief downtime)

**How HPA affects it:**
- HPA doesn't directly affect VPA mode
- But HPA scaling changes workload = VPA adjusts recommendations

**How VPA affects it:**
- This IS the VPA status
- Shows VPA's operational state

---

## Error & Status Metrics

### 20. HTTP Error Rate

**⚠️ IMPORTANT: DeathStarBench services use Thrift RPC, not HTTP, so HTTP error metrics are NOT available.**

**Alternative: Monitor pod restarts and container failures as error indicators:**

**PromQL Query:**
```promql
# Pod restart count (indicates errors/crashes)
sum(kube_pod_container_status_restarts_total{pod=~"user-service-deployment-.*"}) by (pod)

# Container state (0=Running, 1=Waiting, 2=Terminated)
kube_pod_container_status_waiting_reason{pod=~"user-service-deployment-.*"}

# Container ready state (0=NotReady, 1=Ready)
kube_pod_container_status_ready{pod=~"user-service-deployment-.*"}

# If HTTP metrics were available (for reference):
# sum(rate(http_requests_total{service="user-service", status_code=~"5.."}[5m])) by (pod)
# sum(rate(http_requests_total{service="user-service", status_code=~"4.."}[5m])) by (pod)
```

**What it means:**
- **Pod restarts**: High restart count indicates errors/crashes
- **Container state**: Waiting/Terminated states indicate problems
- **Container ready**: Not ready = service unavailable (error condition)
- **Note**: These are indirect error indicators, not direct HTTP error metrics

**Why it's important:**
- High error rate = system is failing
- 5xx errors = server problems (overload, crashes)
- 4xx errors = client problems (bad requests)

**Normal ranges:**
- **<1% error rate**: Good
- **1-5% error rate**: Acceptable but monitor
- **>5% error rate**: Problem

**Abnormal ranges:**
- **>10% error rate**: Critical, immediate action needed
- **>50% error rate**: System is failing

**How HPA affects it:**
- More pods = less load per pod = fewer errors
- HPA scaling up can reduce error rate

**How VPA affects it:**
- Better resources = fewer errors (less overload)
- Insufficient resources = more errors

---

### 21. Pod Restart Count

**PromQL Query:**
```promql
# Pod restart count
sum(increase(kube_pod_container_status_restarts_total{pod=~"user-service-deployment-.*"}[5m])) by (pod)

# Restart rate
rate(kube_pod_container_status_restarts_total{pod=~"user-service-deployment-.*"}[5m])
```

**What it means:**
- How many times pods have restarted
- Restarts = pods crashed or were killed

**Why it's important:**
- High restart count = pods are unstable
- OOM kills show up as restarts
- Indicates resource or application issues

**Normal ranges:**
- **0 restarts**: Ideal
- **1-2 restarts per hour**: Acceptable (may be during deployment)
- **>5 restarts per hour**: Problem

**Abnormal ranges:**
- **>10 restarts per hour**: Critical, pods are very unstable
- **Continuous restarts**: Pods are in crash loop

**How HPA affects it:**
- More pods = less load per pod = fewer restarts
- But HPA doesn't directly cause restarts

**How VPA affects it:**
- VPA adjusting resources can cause restarts (if in Recreate mode)
- But VPA optimizing resources reduces OOM-related restarts

---

## Quick Reference: Key Metrics Dashboard

### Essential Metrics for Your Experiments

**Performance (Latency Target: <500ms)**
1. **Latency from k6 tests** (primary source):
   ```bash
   jq '.metrics.http_req_duration.values.p95' k6-results/*.json
   jq '.metrics.http_req_duration.values.p99' k6-results/*.json
   ```
2. **CPU usage** (proxy indicator): `sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*"}[5m])) by (pod) * 1000`
3. **CPU throttling** (latency indicator): `sum(rate(container_cpu_cfs_throttled_seconds_total{pod=~"user-service-deployment-.*"}[5m])) by (pod)`
   **Note**: HTTP latency histograms not available (services use Thrift)

**Throughput**
4. Requests per second (proxy): `sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*"}[5m])) * 1000`
5. RPS per pod (proxy): `sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*"}[5m])) by (pod) * 1000`
   **Note**: HTTP metrics not available (services use Thrift). CPU usage is a proxy for request rate.

**Resource Utilization (HPA Metrics)**
6. CPU usage %: `rate(container_cpu_usage_seconds_total{...}[5m]) / container_spec_cpu_request{...} * 100`
7. Memory usage %: `container_memory_working_set_bytes{...} / container_spec_memory_request_bytes{...} * 100`

**Scaling Status**
8. Pod replica count: `count(kube_pod_info{...})`
9. HPA desired replicas: `kube_horizontalpodautoscaler_status_desired_replicas{...}`
10. HPA current replicas: `kube_horizontalpodautoscaler_status_current_replicas{...}`

**Health**
11. Error indicators: `sum(kube_pod_container_status_restarts_total{pod=~"user-service-deployment-.*"}) by (pod)`
   **Note**: HTTP error metrics not available (services use Thrift). Use pod restarts as error indicator.
12. Pod ready status: `sum(kube_pod_status_condition{condition="Ready", status="true"})`

**VPA**
13. VPA CPU recommendation: `vpa_recommendation{resource="cpu", ...}`
14. VPA Memory recommendation: `vpa_recommendation{resource="memory", ...}`

---

## Grafana Dashboard Setup

### Recommended Panels

1. **Latency Panel** (Line Graph)
   - p50, p95, p99 latency
   - Y-axis: milliseconds
   - Alert: p95 > 500ms

2. **Throughput Panel** (Line Graph)
   - Total RPS
   - RPS per pod
   - Y-axis: requests/second

3. **CPU Usage Panel** (Line Graph)
   - CPU usage %
   - CPU usage per pod
   - Y-axis: percentage
   - Alert: >80% consistently

4. **Memory Usage Panel** (Line Graph)
   - Memory usage %
   - Memory usage per pod
   - Y-axis: percentage
   - Alert: >90%

5. **Pod Count Panel** (Stat)
   - Current replicas
   - Desired replicas
   - Difference

6. **Error Rate Panel** (Line Graph)
   - Error rate %
   - 5xx errors
   - Y-axis: percentage
   - Alert: >5%

7. **HPA Status Panel** (Table)
   - Desired vs Current replicas
   - Scaling gap

8. **VPA Recommendations Panel** (Gauge)
   - CPU recommendation vs current
   - Memory recommendation vs current

---

## Notes on Metric Names

**Important:** Prometheus metric names may vary depending on:
- Kubernetes version
- Metrics server version
- Application instrumentation
- Service mesh (if used)

**Common variations:**
- `container_cpu_usage_seconds_total` vs `cpu_usage_seconds_total`
- `http_request_duration_seconds` vs `http_server_request_duration_seconds`
- **⚠️ IMPORTANT**: DeathStarBench services use Thrift RPC, not HTTP, so `http_requests_total` metrics are NOT available
- Use `container_cpu_usage_seconds_total` and `container_network_receive_bytes_total` as proxies for request rate
- Use `kube_pod_container_status_restarts_total` as an error indicator

**To find your actual metric names:**
```bash
# List all metrics
kubectl exec -n monitoring prometheus-pod-name -- wget -qO- http://localhost:9090/api/v1/label/__name__/values

# Search for specific metrics
kubectl exec -n monitoring prometheus-pod-name -- wget -qO- http://localhost:9090/api/v1/label/__name__/values | grep -i cpu
kubectl exec -n monitoring prometheus-pod-name -- wget -qO- http://localhost:9090/api/v1/label/__name__/values | grep -i http
```

Or use Prometheus UI:
- Go to `http://your-prometheus:9090`
- Click "Graph" → Type metric name prefix → See autocomplete suggestions

---

## Summary

This guide provides 21 key metrics to track in Prometheus/Grafana. Focus on:

1. **Latency** (p50, p95, p99) - Your primary performance target
2. **CPU/Memory usage** - HPA scaling triggers
3. **Pod replica count** - HPA behavior
4. **Error rate** - System health
5. **VPA recommendations** - Resource optimization

Use these metrics to:
- Understand system behavior during load tests
- Identify when HPA/VPA are working correctly
- Optimize autoscaling configurations
- Achieve your <500ms latency target while minimizing cost



3. **Calculate cost:**
   - Use GCP Pricing Calculator
   - Formula: `(Pod Count × CPU × Memory × Hours) × GCP Pricing`

### Recommended Dashboard Panels

#### Panel 1: Latency (p95/p99)
- **Query:** Extract from k6 JSON results (HTTP latency metrics not available in Prometheus)
  ```bash
  jq '.metrics.http_req_duration.values.p95' k6-results/*.json
  jq '.metrics.http_req_duration.values.p99' k6-results/*.json
  ```
- **Alternative Prometheus Query:** CPU usage as latency proxy
  ```promql
  sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*"}[5m])) by (pod) * 1000
  ```
- **Visualization:** Time series
- **Y-axis:** Milliseconds (k6) or Millicores (CPU proxy)

#### Panel 2: Throughput
- **Query:** `rate(k6_http_reqs_total[5m])` or from k6 JSON
- **Visualization:** Time series
- **Y-axis:** Requests/second

#### Panel 3: CPU Usage
- **Query:** `100 * rate(container_cpu_usage_seconds_total{pod=~"user-service.*"}[5m])`
- **Visualization:** Time series
- **Y-axis:** Percentage

#### Panel 4: Memory Usage
- **Query:** `container_memory_usage_bytes{pod=~"user-service.*"} / 1024 / 1024`
- **Visualization:** Time series
- **Y-axis:** Megabytes

#### Panel 5: Pod Count
- **Query:** `count(kube_pod_info{pod=~"user-service.*"})`
- **Visualization:** Time series
- **Y-axis:** Number of pods

#### Panel 6: Error Rate
- **Query:** `rate(k6_http_req_failed_total[5m])` or from k6 JSON
- **Visualization:** Time series
- **Y-axis:** Error rate (0-1)

### Import Pre-built Dashboards

Grafana has many pre-built dashboards:

1. **Kubernetes Cluster Monitoring** (ID: 7249)
   - Comprehensive Kubernetes metrics

2. **Node Exporter Full** (ID: 1860)
   - Node-level metrics

3. **cAdvisor** (ID: 14282)
   - Container metricsJ

- `unique-id-service`
- `social-graph-service`
- `nginx-thrift`
- `compose-post-service`
- `home-timeline-service`
- `media-service`
- `post-storage-service`
- `text-service`
- `url-shorten-service`
- `user-mention-service`
- `user-timeline-service`