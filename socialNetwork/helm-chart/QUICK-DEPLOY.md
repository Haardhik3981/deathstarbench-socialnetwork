# Quick Deploy - Social Network with Monitoring

Complete setup guide for deploying the Social Network application with Prometheus + Grafana monitoring on Nautilus.

---

## Prerequisites

- `kubectl` configured for Nautilus cluster
- `helm` installed
- Namespace: `cse239fall2025`

---

## Step 1: Deploy Application

```bash
cd "/Users/haardhikmudagereanil/Downloads/MSCS - UCSC/Q4/CSE239_AdvCloudComputing/Project/DeathStarBench_project_root/DeathStarBench/socialNetwork/helm-chart"

cd socialnetwork
helm install dsb-socialnetwork . -n cse239fall2025 --set global.prometheus.enabled=true

# Wait for all pods to be Running
kubectl get pods -n cse239fall2025 -w
```

---

## Step 2: Deploy Monitoring Stack

```bash
cd ../monitoring

kubectl apply -f prometheus-config.yaml -n cse239fall2025
kubectl apply -f prometheus.yaml -n cse239fall2025
kubectl apply -f pushgateway-deployment.yaml -n cse239fall2025
kubectl apply -f grafana-datasources.yaml -n cse239fall2025
kubectl apply -f grafana.yaml -n cse239fall2025

# Verify
kubectl get pods -n cse239fall2025 | grep -E "(prometheus|grafana|pushgateway)"
```

---

## Step 3: Port-Forward (4 Terminals)

| Terminal | Command |
|----------|---------|
| 1 | `kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025` |
| 2 | `kubectl port-forward svc/grafana 3000:3000 -n cse239fall2025` |
| 3 | `kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025` |
| 4 | Run metrics collector (see Step 4) |

---

## Step 4: Start Metrics Collector

```bash
cd scripts
./push-metrics-loop.sh 10
```

This collects CPU/Memory for 11 microservices every 10 seconds:
- nginx-thrift, compose-post-service, home-timeline-service
- user-timeline-service, post-storage-service, social-graph-service
- text-service, user-service, unique-id-service
- url-shorten-service, user-mention-service

---

## Step 5: Import Grafana Dashboard

1. Open http://localhost:3000
2. Login: `admin` / `admin`
3. Go to **Dashboards → Import**
4. Upload: `monitoring/grafana-dashboard.json`

---

## Step 6: Run Load Tests

```bash
cd scripts

# Deploy test scripts
kubectl apply -f k6-configmap.yaml -n cse239fall2025

# Run Load Test (14 min)
kubectl apply -f k6-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-load-test

# OR Stress Test (15 min)
kubectl apply -f k6-stress-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test
```

---

## Available Metrics

| Metric | Query | Source |
|--------|-------|--------|
| CPU (millicores) | `ha_cpu_usage_millicores` | Pushgateway |
| Memory (MiB) | `ha_memory_usage_bytes / 1024 / 1024` | Pushgateway |
| Request Rate | `rate(nginx_http_requests_total[1m])` | nginx |
| Throughput | `sum(rate(nginx_http_requests_total[30s]))` | nginx |
| Connections | `nginx_connections_active` | nginx |

---

## Dashboard Panels

The Grafana dashboard includes:

**Resource Metrics:**
- CPU Usage (millicores) - per pod
- Memory Usage (MiB) - per pod  
- Total CPU/Memory - aggregated
- CPU by Pod (Stacked)
- Resource Table with gauges

**Traffic Metrics:**
- Request Rate (RPS)
- Throughput (Requests/sec)
- Active Connections
- Total Requests

---

## Cleanup

```bash
# Stop port-forwards (Ctrl+C)
# Stop metrics collector (Ctrl+C)

# Delete K6 jobs
kubectl delete job k6-load-test k6-stress-test -n cse239fall2025 2>/dev/null || true

# Delete monitoring
cd monitoring
kubectl delete -f grafana.yaml -n cse239fall2025
kubectl delete -f grafana-datasources.yaml -n cse239fall2025
kubectl delete -f prometheus.yaml -n cse239fall2025
kubectl delete -f prometheus-config.yaml -n cse239fall2025
kubectl delete -f pushgateway-deployment.yaml -n cse239fall2025

# Delete application
helm uninstall dsb-socialnetwork -n cse239fall2025
```

---

## File Reference

| File | Purpose |
|------|---------|
| `monitoring/prometheus-config.yaml` | Prometheus scrape config |
| `monitoring/prometheus.yaml` | Prometheus deployment |
| `monitoring/grafana.yaml` | Grafana deployment |
| `monitoring/grafana-datasources.yaml` | Prometheus datasource |
| `monitoring/grafana-dashboard.json` | Dashboard to import |
| `monitoring/pushgateway-deployment.yaml` | Pushgateway for metrics |
| `scripts/push-metrics-loop.sh` | CPU/Memory collector |
| `scripts/k6-*.yaml` | Load test jobs |
