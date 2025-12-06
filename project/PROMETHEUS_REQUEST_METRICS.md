# Prometheus/Grafana Queries for Request Rate Monitoring

This guide provides PromQL queries to track request rates and verify that new pods are handling traffic when autoscaling occurs.

## Quick Setup

### Access Prometheus/Grafana

If Prometheus is installed:
```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then open http://localhost:9090 in your browser
```

If Grafana is installed:
```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Then open http://localhost:3000 (default: admin/admin)
```

---

## Core Queries: Request Rate Per Service

### 1. Total Request Rate (All Pods Combined)

**Query:**
```promql
# Total requests per second for user-service (all pods)
sum(rate(http_requests_total{service="user-service"}[1m])) by (service)
```

**Alternative (if metric name differs):**
```promql
# Try these variations if the above doesn't work:
sum(rate(http_request_total{service="user-service"}[1m]))
sum(rate(nginx_http_requests_total{service="user-service"}[1m]))
sum(rate(requests_total{service="user-service"}[1m]))
```

**What it shows:**
- Total requests/second handled by all pods of a service
- When new pods come up, this should increase (more capacity)

---

### 2. Request Rate Per Pod

**Query:**
```promql
# Requests per second per pod for user-service
sum(rate(http_requests_total{service="user-service"}[1m])) by (pod)
```

**What it shows:**
- How many requests each pod is handling
- When a new pod appears, you'll see a new line
- Initially, new pods will have lower RPS (just starting)
- Over time, RPS should distribute across all pods

**Visualization:**
- **Graph**: Shows each pod as a separate line
- **Table**: Shows pod name and current RPS
- **Watch for**: New pod lines appearing when scaling occurs

---

### 3. Request Rate Per Pod (with Pod Names)

**Query:**
```promql
# Requests per second per pod with readable labels
sum(rate(http_requests_total{service="user-service"}[1m])) by (pod, instance)
```

**What it shows:**
- Same as above, but with instance labels for clarity
- Easier to identify which pod is which

---

## Combined Queries: Pod Count + Request Rate

### 4. Total Request Rate + Pod Count (Side by Side)

**Query 1 - Request Rate:**
```promql
sum(rate(http_requests_total{service="user-service"}[1m]))
```

**Query 2 - Pod Count:**
```promql
count(count(rate(http_requests_total{service="user-service"}[1m])) by (pod))
```

**What it shows:**
- Two metrics on the same graph
- Request rate should increase when pod count increases
- Verifies that new pods are actually handling traffic

---

### 5. Average Request Rate Per Pod

**Query:**
```promql
# Average requests per second per pod
avg(sum(rate(http_requests_total{service="user-service"}[1m])) by (pod))
```

**What it shows:**
- Average load per pod
- Should decrease when new pods are added (load distribution)
- Should increase when pods are removed (load concentration)

---

## Network-Based Metrics (If HTTP Metrics Not Available)

If your services don't expose `http_requests_total`, you can use network metrics as a proxy:

### 6. Network Traffic Per Pod (Proxy for Request Rate)

**Query:**
```promql
# Network bytes transmitted per second per pod (proxy for request rate)
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[1m])) by (pod)
```

**What it shows:**
- Network traffic per pod (bytes/second)
- Higher traffic = more requests being handled
- New pods will show increasing traffic as they start receiving requests

**Note:** This is a proxy metric - actual request count is better, but this works if HTTP metrics aren't available.

---

### 7. Network Traffic Total (All Pods)

**Query:**
```promql
# Total network traffic for user-service (all pods)
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[1m]))
```

**What it shows:**
- Total outgoing network traffic
- Should increase when new pods are added and start handling traffic

---

## Nginx-Thrift Specific Queries

Since nginx-thrift is your ingress, it may expose different metrics:

### 8. Nginx Request Rate

**Query:**
```promql
# Total requests per second through nginx-thrift
sum(rate(nginx_http_requests_total{service="nginx-thrift"}[1m]))
```

**Alternative:**
```promql
# If nginx exposes metrics differently
sum(rate(nginx_connections_active{service="nginx-thrift"}[1m]))
```

---

## Pod Status + Request Rate Combined

### 9. Pod Count Over Time

**Query:**
```promql
# Number of running pods for user-service
count(kube_pod_status_phase{pod=~"user-service-deployment-.*", phase="Running"})
```

**What it shows:**
- Number of pods over time
- Step increases when HPA scales up
- Step decreases when HPA scales down

**Combine with request rate:**
- Create two panels: one for pod count, one for request rate
- Watch pod count increase → request rate should increase shortly after

---

## Grafana Dashboard Queries

### 10. Complete Dashboard Query Set

**Panel 1: Total Request Rate**
```promql
sum(rate(http_requests_total{service="user-service"}[1m]))
```

**Panel 2: Request Rate Per Pod**
```promql
sum(rate(http_requests_total{service="user-service"}[1m])) by (pod)
```

**Panel 3: Pod Count**
```promql
count(count(rate(http_requests_total{service="user-service"}[1m])) by (pod))
```

**Panel 4: Average RPS Per Pod**
```promql
avg(sum(rate(http_requests_total{service="user-service"}[1m])) by (pod))
```

**Panel 5: CPU Usage Per Pod (for context)**
```promql
sum(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*", container!="POD"}[1m])) by (pod) * 1000
```

---

## How to Verify New Pods Are Working

### Step-by-Step Verification:

1. **Before Scaling:**
   - Note current request rate: `X requests/sec`
   - Note current pod count: `N pods`

2. **During Scaling:**
   - Watch pod count query → should increase
   - Watch request rate per pod → new pod should appear with low/zero RPS

3. **After Scaling (10-20 seconds):**
   - New pod should start showing RPS > 0
   - Total request rate should increase (more capacity)
   - Average RPS per pod should decrease (load distribution)

4. **Verification:**
   - ✅ New pod appears in "Request Rate Per Pod" query
   - ✅ New pod RPS increases from 0 to > 0
   - ✅ Total request rate increases
   - ✅ Average RPS per pod decreases (load distributing)

---

## Troubleshooting: If Metrics Don't Appear

### Check Available Metrics:

1. **List all metrics in Prometheus:**
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Then visit http://localhost:9090/graph
   # Click "Metrics" dropdown to see all available metrics
   ```

2. **Search for HTTP-related metrics:**
   - Look for: `http_requests`, `http_request`, `requests_total`, `nginx_http_requests`

3. **Check if services expose metrics:**
   ```bash
   # Port-forward to a service pod
   kubectl port-forward pod/user-service-deployment-xxx 9090:9090
   # Then curl http://localhost:9090/metrics
   ```

4. **Check Prometheus targets:**
   ```bash
   # In Prometheus UI, go to Status → Targets
   # Verify services are being scraped
   ```

---

## Alternative: Use Network Metrics

If HTTP request metrics aren't available, use network traffic as a proxy:

**Query:**
```promql
# Network traffic per pod (proxy for request rate)
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[1m])) by (pod)
```

**What to look for:**
- New pods will show increasing network traffic
- Total network traffic increases when new pods start handling requests
- Not as precise as request count, but shows activity

---

## Example: What You Should See

### Timeline During Autoscaling:

```
Time 0s:   Traffic spike starts
Time 0s:   Request rate: 100 req/s, Pods: 1
Time 5s:   Request rate: 200 req/s, Pods: 1 (overloaded)
Time 10s:  HPA scales up → Pods: 2 (new pod created)
Time 15s:  Request rate: 150 req/s per pod, Pods: 2
           - Old pod: 100 req/s
           - New pod: 50 req/s (just starting)
Time 20s:  Request rate: 100 req/s per pod, Pods: 2
           - Old pod: 100 req/s
           - New pod: 100 req/s (fully distributing)
Time 25s:  Total request rate: 200 req/s, Pods: 2
           - System can now handle more load ✅
```

---

## Quick Reference: All Services

Replace `user-service` with any service name:

- `unique-id-service`
- `social-graph-service`
- `nginx-thrift`
- `compose-post-service`
- `home-timeline-service`
- etc.

**Example:**
```promql
# Request rate for unique-id-service
sum(rate(http_requests_total{service="unique-id-service"}[1m]))
```

---

## Next Steps

1. **Try the queries** in Prometheus/Grafana
2. **Identify which metrics are available** in your setup
3. **Create a dashboard** with pod count + request rate panels
4. **Run your peak test** and watch the metrics in real-time
5. **Verify** that new pods start handling traffic within 10-20 seconds

If you need help finding the right metric names for your setup, check Prometheus's metrics list or let me know what metrics are available!

