# Prometheus Guide for Beginners

## What is Prometheus?

Prometheus is a **monitoring and alerting toolkit**. Think of it as a **time-series database** that:
- Collects metrics from your services (CPU, memory, request counts, latency, etc.)
- Stores these metrics over time
- Lets you query and analyze the data
- Can trigger alerts when things go wrong

## What Prometheus Does vs. What You Do With It

### What Prometheus Does Automatically:
1. **Scrapes metrics** from your services every 15 seconds (by default)
2. **Stores the data** in a time-series database
3. **Discovers new services** automatically (Kubernetes service discovery)
4. **Keeps historical data** (configured retention period)

### What You Do With Prometheus:
1. **Check if services are up** (Targets page) ✅
2. **Query metrics** to understand performance (Graph page) 📊
3. **Set up alerts** (when CPU > 80%, requests failing, etc.) 🚨
4. **Visualize in Grafana** (create dashboards) 📈
5. **Debug performance issues** (why is my service slow?)

## Understanding the Prometheus UI

### 1. **Targets Page** (Status > Targets)

**What it shows:**
- Which services Prometheus is successfully scraping
- Health status (UP/DOWN)
- Last scrape time
- Any errors

**What you see:**
- Green = Service is UP and being scraped ✅
- Red = Service is DOWN or has errors ❌
- Endpoint links (these won't work in your browser - that's normal!)

**Why endpoint links show "site can't be reached":**
- Those URLs are **internal Kubernetes addresses** (like `kubernetes.default.svc`)
- They only work **inside the Kubernetes cluster**
- Your browser tries to access them from your computer, which doesn't work
- **This is completely normal and not a problem!** ✅
- Prometheus itself can access them (that's what matters)

**What to do here:**
- Just check that services show as "UP" (green)
- If you see errors, that's what you need to fix
- You don't need to click the endpoint links - they're just for reference

### 2. **Graph Page** (Main Page)

**This is where you actually query metrics!**

**What you can do:**
- Type queries in the expression box
- See results as a graph or table
- Look at metrics over time
- Export data

**Common queries to try:**

```
# CPU usage for all containers
rate(container_cpu_usage_seconds_total[5m])

# Memory usage for a specific pod
container_memory_usage_bytes{pod=~"user-service.*"}

# Request rate (if your services expose HTTP metrics)
rate(http_requests_total[5m])

# See all available metrics (just type the metric name)
container_cpu_usage_seconds_total
```

**How to use it:**
1. Type a query in the expression box
2. Click "Execute"
3. See the results below
4. Switch to "Graph" view to see trends over time

### 3. **Status > Configuration**

**What it shows:**
- The Prometheus configuration file
- What scrape jobs are configured
- How often metrics are collected

**When to check:**
- To verify your configuration is correct
- To see what services are being monitored

### 4. **Status > Service Discovery**

**What it shows:**
- All discovered targets (before filtering)
- Labels attached to each target
- Useful for debugging discovery issues

## Practical Examples: What to Actually Do

### Example 1: Monitor CPU Usage

**Goal:** See which pods are using the most CPU

**Query:**
```promql
rate(container_cpu_usage_seconds_total[5m]) * 100
```

**What this does:**
- `container_cpu_usage_seconds_total` - CPU usage metric
- `rate(...[5m])` - Calculate rate over 5 minutes
- `* 100` - Convert to percentage

**Result:** Shows CPU usage as a percentage for each container

### Example 2: Monitor Memory Usage

**Goal:** Find pods using the most memory

**Query:**
```promql
container_memory_usage_bytes / 1024 / 1024
```

**What this does:**
- `container_memory_usage_bytes` - Memory usage in bytes
- `/ 1024 / 1024` - Convert to megabytes

**Result:** Memory usage in MB for each container

### Example 3: Monitor a Specific Service

**Goal:** Track CPU usage for user-service pods

**Query:**
```promql
rate(container_cpu_usage_seconds_total{pod=~"user-service.*"}[5m]) * 100
```

**What this does:**
- `{pod=~"user-service.*"}` - Filter to only user-service pods
- Shows CPU usage over time

### Example 4: Count Running Pods

**Goal:** See how many pods are running

**Query:**
```promql
count(container_memory_usage_bytes)
```

**Result:** Total number of containers with memory metrics

### Example 5: Check Available Metrics

**Goal:** See what metrics are available

**Query:** Just browse the dropdown when typing in the expression box, or:
```promql
{__name__=~".+"}
```

## Common Workflows

### Workflow 1: "Is everything healthy?"

1. Go to **Status > Targets**
2. Check all targets show as "UP" (green)
3. If any are DOWN, check the error message
4. Fix the issues causing DOWN status

### Workflow 2: "Why is my service slow?"

1. Go to **Graph** page
2. Query CPU usage: `rate(container_cpu_usage_seconds_total{pod=~"your-service.*"}[5m])`
3. Query memory usage: `container_memory_usage_bytes{pod=~"your-service.*"}`
4. Look for spikes or high usage
5. Check if resources are exhausted

### Workflow 3: "Monitor during load tests"

1. Start a k6 load test
2. Open Prometheus Graph page
3. Query request rates, CPU, memory
4. Watch metrics change in real-time
5. Identify bottlenecks

### Workflow 4: "Create a dashboard in Grafana"

1. Query metrics in Prometheus to find what you want
2. Copy the query
3. Go to Grafana
4. Create a new dashboard panel
5. Paste the Prometheus query
6. Visualize as graph, gauge, or table

## Important Concepts

### Time-Series Data

Prometheus stores data as **time-series**:
- Each metric has a name (e.g., `container_cpu_usage_seconds_total`)
- Labels identify different instances (e.g., `pod="user-service-123"`)
- Values are stored with timestamps
- You can query historical data

### Labels

Labels are key-value pairs that identify metrics:
- `pod="user-service-abc123"`
- `namespace="default"`
- `container="user-service"`

Use labels to filter queries:
```promql
container_cpu_usage_seconds_total{pod="user-service-abc123"}
```

### Rates vs. Counters

- **Counters**: Always increase (e.g., total requests)
  - Use `rate()` to get per-second rate
  - Example: `rate(http_requests_total[5m])`

- **Gauges**: Can go up or down (e.g., CPU usage, memory)
  - Use directly: `container_memory_usage_bytes`

### Query Functions

Common functions:
- `rate()` - Calculate per-second rate
- `increase()` - Total increase over time
- `sum()` - Sum values
- `avg()` - Average values
- `max()` - Maximum value
- `count()` - Count of series

## Accessing Prometheus

### From Your Computer

```bash
# Port-forward to access Prometheus UI
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Then open in browser
open http://localhost:9090
```

### What You Can Do

- ✅ Query metrics
- ✅ View graphs
- ✅ Check target status
- ✅ Browse configuration
- ❌ Can't click endpoint links (they're internal)
- ✅ Can export data
- ✅ Can set up alerts

## Next Steps

1. **Start Simple:**
   - Open Prometheus Graph page
   - Type: `container_cpu_usage_seconds_total`
   - Click Execute
   - See all CPU metrics

2. **Filter by Service:**
   - Try: `container_cpu_usage_seconds_total{pod=~"user-service.*"}`
   - See CPU for just user-service

3. **Calculate Rates:**
   - Try: `rate(container_cpu_usage_seconds_total[5m])`
   - See CPU usage rate

4. **Create Grafana Dashboard:**
   - Once you know what queries work
   - Create visualizations in Grafana

## Troubleshooting

### "No data points found"

**Possible causes:**
- Metric name doesn't exist (check spelling)
- No data for the selected time range
- Service isn't exposing that metric

**Solution:**
- Check Targets page - is service UP?
- Browse available metrics in the dropdown
- Try a wider time range

### "Expression produces many time series"

**Cause:** Query matches too many metrics

**Solution:** Add filters using labels
```promql
# Too broad:
container_cpu_usage_seconds_total

# Better:
container_cpu_usage_seconds_total{pod=~"user-service.*"}
```

### Endpoint links don't work

**This is normal!** ✅
- Endpoints are internal Kubernetes addresses
- They only work from inside the cluster
- Prometheus can access them (that's what matters)
- You don't need to click them

## Summary

**What Prometheus is:**
- A monitoring tool that collects and stores metrics
- A query engine for analyzing metrics
- A data source for Grafana dashboards

**What you do:**
- Check Targets page to see what's being monitored
- Query Graph page to analyze performance
- Create Grafana dashboards for visualization
- Set up alerts for problems

**Key takeaway:**
The endpoint links showing "site can't be reached" is **completely normal** - they're internal cluster addresses. Focus on:
1. ✅ Making sure targets show as UP
2. ✅ Querying metrics in the Graph page
3. ✅ Creating visualizations in Grafana

## Quick Reference: Common Queries

```promql
# CPU usage (percentage)
rate(container_cpu_usage_seconds_total[5m]) * 100

# Memory usage (MB)
container_memory_usage_bytes / 1024 / 1024

# CPU for specific service
rate(container_cpu_usage_seconds_total{pod=~"user-service.*"}[5m]) * 100

# Memory for specific service
container_memory_usage_bytes{pod=~"user-service.*"} / 1024 / 1024

# Network receive rate (MB/s)
rate(container_network_receive_bytes_total[5m]) / 1024 / 1024

# Number of running containers
count(container_memory_usage_bytes)

# Average CPU across all pods
avg(rate(container_cpu_usage_seconds_total[5m])) * 100
```

Start with these queries, modify them for your needs, and build up from there!

