# Quick Reference: Grafana/Prometheus Queries for Request Rate

## Access Prometheus/Grafana

### Prometheus (Query Interface):
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090
```

### Grafana (Dashboards):
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000
# Default login: admin/admin (or check your setup)
```

---

## Essential Queries for Request Rate Monitoring

### 1. Total Request Rate (All Pods) - PRIMARY QUERY

**Try these in order (one should work):**

```promql
# Option A: Standard HTTP metrics
sum(rate(http_requests_total{service="user-service"}[1m]))

# Option B: Alternative metric name
sum(rate(http_request_total{service="user-service"}[1m]))

# Option C: Network traffic as proxy (always works)
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[1m])) by (pod)
```

**What to look for:**
- Value increases when new pods start handling traffic
- Should see step increases when HPA scales up

---

### 2. Request Rate Per Pod - VERIFY NEW PODS ARE WORKING

```promql
# Request rate per pod
sum(rate(http_requests_total{service="user-service"}[1m])) by (pod)

# Or using network traffic:
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[1m])) by (pod)
```

**What to look for:**
- New pod appears as a new line when scaling occurs
- Initially shows 0 or low value (pod just started)
- Gradually increases as pod receives more traffic
- After 10-20 seconds, should be handling similar load to other pods

**Visualization:**
- Use **Graph** panel with multiple series
- Each pod = one line
- Watch for new lines appearing when scaling

---

### 3. Pod Count Over Time

```promql
# Number of running pods
count(kube_pod_info{pod=~"user-service-deployment-.*"})

# Alternative:
count(count(rate(container_cpu_usage_seconds_total{pod=~"user-service-deployment-.*"}[1m])) by (pod))
```

**What to look for:**
- Step increases when HPA scales up
- Step decreases when HPA scales down
- Should correlate with request rate changes

---

### 4. Combined View: Pod Count + Total Request Rate

**Panel 1 - Pod Count:**
```promql
count(kube_pod_info{pod=~"user-service-deployment-.*"})
```

**Panel 2 - Total Request Rate:**
```promql
sum(rate(http_requests_total{service="user-service"}[1m]))
```

**What to look for:**
- Pod count increases → Request rate should increase shortly after
- Verifies that new pods are actually handling traffic

---

## Complete Grafana Dashboard Setup

### Panel 1: Total Request Rate (All Pods)
```promql
sum(rate(http_requests_total{service="user-service"}[1m]))
```
- **Title:** "Total Request Rate - user-service"
- **Unit:** requests/sec
- **Visualization:** Graph

### Panel 2: Request Rate Per Pod
```promql
sum(rate(http_requests_total{service="user-service"}[1m])) by (pod)
```
- **Title:** "Request Rate Per Pod"
- **Unit:** requests/sec
- **Visualization:** Graph (multiple series)
- **Legend:** Show pod names

### Panel 3: Pod Count
```promql
count(kube_pod_info{pod=~"user-service-deployment-.*"})
```
- **Title:** "Pod Count"
- **Unit:** pods
- **Visualization:** Graph

### Panel 4: Average RPS Per Pod
```promql
avg(sum(rate(http_requests_total{service="user-service"}[1m])) by (pod))
```
- **Title:** "Average RPS Per Pod"
- **Unit:** requests/sec
- **Visualization:** Graph
- **What to look for:** Should decrease when new pods are added (load distribution)

---

## What You Should See During Autoscaling

### Timeline Example:

```
Time 0s:   Traffic spike starts
           Pod Count: 1
           Total RPS: 100 req/s
           Per Pod: 100 req/s (overloaded)

Time 10s:  HPA scales up
           Pod Count: 2 (new pod created)
           Total RPS: 100 req/s (still same, new pod not ready yet)
           Per Pod: 
             - Old pod: 100 req/s
             - New pod: 0 req/s (not receiving traffic yet)

Time 15s:  New pod becomes ready
           Pod Count: 2
           Total RPS: 120 req/s (increasing - new pod helping!)
           Per Pod:
             - Old pod: 80 req/s (load distributing)
             - New pod: 40 req/s (starting to help)

Time 20s:  Load fully distributed
           Pod Count: 2
           Total RPS: 150 req/s (system can handle more now!)
           Per Pod:
             - Old pod: 75 req/s (healthy)
             - New pod: 75 req/s (healthy)
```

**Key Indicators:**
- ✅ Pod count increases
- ✅ New pod line appears in "Request Rate Per Pod"
- ✅ New pod RPS increases from 0
- ✅ Total RPS increases (more capacity)
- ✅ Average RPS per pod decreases (load distributing)

---

## If HTTP Metrics Aren't Available

Use network traffic as a proxy:

### Network Traffic Per Pod:
```promql
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[1m])) by (pod)
```

**What it shows:**
- Bytes transmitted per second per pod
- Higher bytes = more requests being handled
- New pods will show increasing traffic as they start receiving requests

**Limitations:**
- Not as precise as request count
- Includes all network traffic (not just HTTP)
- But works if HTTP metrics aren't exposed

---

## For All Services

Replace `user-service` with any service:

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

**Example:**
```promql
# Request rate for unique-id-service
sum(rate(http_requests_total{service="unique-id-service"}[1m]))
```

---

## Troubleshooting

### If queries return "no data":

1. **Check if metrics exist:**
   - In Prometheus UI, go to "Graph" tab
   - Click "Metrics" dropdown
   - Search for "http" or "request"

2. **Check if services are being scraped:**
   - In Prometheus UI, go to "Status → Targets"
   - Verify services show as "UP"

3. **Try network metrics instead:**
   - Use `container_network_transmit_bytes_total` (always available)

4. **Check service labels:**
   - Metrics might use different label names
   - Try: `service`, `job`, `instance`, `pod`

### Finding the Right Metric Name:

```bash
# Run this script to discover metrics:
./scripts/check-prometheus-metrics.sh

# Or query Prometheus API directly:
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then visit: http://localhost:9090/api/v1/label/__name__/values
```

---

## Quick Test

1. **Start port-forward:**
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   ```

2. **Open Prometheus:**
   - http://localhost:9090

3. **Try this query:**
   ```promql
   sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[1m])) by (pod)
   ```

4. **Run your peak test** and watch the graph
5. **You should see:**
   - New pod lines appearing when scaling occurs
   - Traffic increasing on new pods
   - Total traffic increasing

---

## Summary

**Best Query to Start With:**
```promql
sum(rate(container_network_transmit_bytes_total{pod=~"user-service-deployment-.*"}[1m])) by (pod)
```

This will show network traffic per pod, which is a good proxy for request rate and will definitely work (it's a standard Kubernetes metric).

**What to Verify:**
1. New pods appear as new lines when scaling occurs
2. New pods show increasing traffic (from 0 to higher values)
3. Total traffic increases when new pods start helping
4. Load distributes across all pods

This confirms that new pods are working and increasing system capacity! 🎯

