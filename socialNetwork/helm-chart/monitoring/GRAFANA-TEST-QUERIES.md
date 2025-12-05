# Grafana Test Queries - Copy & Paste

Go to Grafana → **Explore** tab, then paste these queries one by one:

---

## Basic Queries (Start Here)

### 1. Check Nginx is Being Scraped
```promql
up{job="nginx-frontend"}
```
**Expected:** Shows `1` (means nginx target is UP)

### 2. Total HTTP Requests
```promql
nginx_http_requests_total
```
**Expected:** Shows a number (might be small if no traffic yet)

### 3. Active Connections Right Now
```promql
nginx_connections_active
```
**Expected:** Shows current number of active connections (probably 1-3)

### 4. All Nginx Metrics (Explore)
```promql
{job="nginx-frontend"}
```
**Expected:** Shows all metrics from nginx-prometheus-exporter

---

## Request Rate Queries

### 5. Requests Per Second (Last 5 Minutes)
```promql
rate(nginx_http_requests_total[5m])
```
**Expected:** Shows requests/second average over last 5 minutes

### 6. Requests Per Minute (Instant)
```promql
rate(nginx_http_requests_total[1m])
```
**Expected:** More granular - shows last 1 minute average

### 7. Total New Requests (Last Minute)
```promql
increase(nginx_http_requests_total[1m])
```
**Expected:** How many NEW requests in the last minute

---

## Connection Metrics

### 8. All Connection States
```promql
nginx_connections_active
nginx_connections_reading
nginx_connections_writing
nginx_connections_waiting
```
**Paste all 4 separately or use multi-query:**
- Active = total connections
- Reading = reading request headers
- Writing = sending response
- Waiting = idle keepalive

### 9. Connection Acceptance Rate
```promql
rate(nginx_connections_accepted[5m])
```
**Expected:** New connections per second

---

## Advanced Queries

### 10. Total Connections Accepted (Counter)
```promql
nginx_connections_accepted
```
**Expected:** Total connections since nginx started

### 11. Connection Handling Ratio
```promql
nginx_connections_handled / nginx_connections_accepted
```
**Expected:** Should be 1.0 (means all connections were handled successfully)

### 12. Requests Per Connection
```promql
nginx_http_requests_total / nginx_connections_handled
```
**Expected:** Average requests per connection (HTTP keepalive efficiency)

---

## Monitoring Prometheus Itself

### 13. Prometheus Scrape Duration
```promql
scrape_duration_seconds{job="nginx-frontend"}
```
**Expected:** How long each scrape takes (should be milliseconds)

### 14. Prometheus Up Status
```promql
up
```
**Expected:** Shows all targets (prometheus, nginx-frontend, pushgateway)

### 15. Prometheus Memory Usage
```promql
process_resident_memory_bytes{job="prometheus"}
```
**Expected:** Prometheus's own memory usage in bytes

---

## Test by Generating Traffic

Run this in your terminal while watching Grafana:

```bash
# Port-forward nginx
kubectl port-forward -n cse239fall2025 deployment/nginx-thrift 8080:8080 &

# Generate 100 requests
for i in {1..100}; do
  curl -s http://localhost:8080/ > /dev/null
  echo "Request $i"
  sleep 0.1
done

pkill -f "port-forward.*8080"
```

While this runs, watch these queries in Grafana (set auto-refresh to 5s):

```promql
rate(nginx_http_requests_total[30s])
nginx_connections_active
increase(nginx_http_requests_total[1m])
```

You should see the values spike! 📈

---

## Creating Your First Dashboard

1. After testing queries in Explore
2. Click **Add to dashboard** button (top right)
3. Or go to **+ → Dashboard → Add visualization**
4. Add these panels:

**Panel 1:** Request Rate
- Query: `rate(nginx_http_requests_total[5m])`
- Viz: Time series

**Panel 2:** Active Connections
- Query: `nginx_connections_active`
- Viz: Stat (big number)

**Panel 3:** Total Requests
- Query: `nginx_http_requests_total`
- Viz: Stat

**Panel 4:** Connection States
- Query 1: `nginx_connections_reading`
- Query 2: `nginx_connections_writing`
- Query 3: `nginx_connections_waiting`
- Viz: Time series (stacked)

Save the dashboard as "Social Network Monitoring"

---

## Quick Verification Checklist

Try these queries in order to verify everything works:

- [ ] `up{job="nginx-frontend"}` → Returns 1
- [ ] `nginx_http_requests_total` → Returns a number
- [ ] `nginx_connections_active` → Returns 1-10
- [ ] `rate(nginx_http_requests_total[5m])` → Returns a number (might be 0 if no traffic)
- [ ] Generate traffic → See values change
- [ ] Create a panel → Save dashboard

If ALL of these work, you're ready to go! 🚀

