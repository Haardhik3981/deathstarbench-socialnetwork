# Commands Only - Complete Setup Guide

**Copy-paste these commands in order.**

---

## Step 1: Cleanup (Optional - if redeploying)

```bash
cd "/Users/haardhikmudagereanil/Downloads/MSCS - UCSC/Q4/CSE239_AdvCloudComputing/Project/DeathStarBench_project_root/DeathStarBench/socialNetwork/helm-chart"

helm uninstall dsb-socialnetwork -n cse239fall2025 2>/dev/null || true

kubectl delete -f monitoring/grafana.yaml -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/grafana-datasources.yaml -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/prometheus.yaml -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/prometheus-config.yaml -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/pushgateway-deployment.yaml -n cse239fall2025 2>/dev/null || true

kubectl get pods -n cse239fall2025 --no-headers | grep -E "(Error|Terminating)" | awk '{print $1}' | xargs -I {} kubectl delete pod {} -n cse239fall2025 --force --grace-period=0 2>/dev/null || true

sleep 10
kubectl get pods -n cse239fall2025
```

---

## Step 2: Deploy Application

```bash
cd socialnetwork

helm install dsb-socialnetwork . -n cse239fall2025 --set global.prometheus.enabled=true

# Wait for pods to be ready
kubectl get pods -n cse239fall2025 -w
# Press Ctrl+C when all pods show Running
```

---

## Step 3: Deploy Monitoring Stack

```bash
cd ../monitoring

kubectl apply -f prometheus-config.yaml -n cse239fall2025
kubectl apply -f prometheus.yaml -n cse239fall2025
kubectl apply -f pushgateway-deployment.yaml -n cse239fall2025
kubectl apply -f grafana-datasources.yaml -n cse239fall2025
kubectl apply -f grafana.yaml -n cse239fall2025

# Verify monitoring pods
kubectl get pods -n cse239fall2025 | grep -E "(prometheus|grafana|pushgateway)"
```

---

## Step 4: Port-Forward Services (3 Terminals)

**Terminal 1 - Prometheus:**
```bash
kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025
```

**Terminal 2 - Grafana:** #Optional | Access at grafana-haardhik.nrp-nautilus.io
```bash
kubectl port-forward svc/grafana 3000:3000 -n cse239fall2025
```

**Terminal 3 - Pushgateway:**
```bash
kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025
```

---

## Step 5: Import Grafana Dashboard

1. Open http://localhost:3000
2. Login: `admin` / `admin`
3. Go to: **Dashboards → Import**
4. Click **Upload JSON file**
5. Select: `monitoring/grafana-dashboard.json`
6. Click **Import**

---

## Step 6: Start Metrics Collector

**Terminal 4 - Metrics Collector:**
```bash
cd "/Users/haardhikmudagereanil/Downloads/MSCS - UCSC/Q4/CSE239_AdvCloudComputing/Project/DeathStarBench_project_root/DeathStarBench/socialNetwork/helm-chart/scripts"

./push-metrics-loop.sh 10
```

This pushes CPU/Memory metrics every 10 seconds for these 11 microservices:
- nginx-thrift
- compose-post-service
- home-timeline-service
- user-timeline-service
- post-storage-service
- social-graph-service
- text-service
- user-service
- unique-id-service
- url-shorten-service
- user-mention-service

---

## Step 7: Run Load Tests

```bash
cd scripts

# Deploy K6 test scripts
kubectl apply -f k6-configmap.yaml -n cse239fall2025

# Run Load Test (14 min, 100 users)
kubectl apply -f k6-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-load-test

# OR Run Stress Test (15 min, 600 users)
kubectl delete job k6-load-test -n cse239fall2025 2>/dev/null || true
kubectl apply -f k6-stress-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test
```

---

## Step 8: View Metrics in Grafana

Open http://localhost:3000 and view the dashboard:

**Available Metrics:**

| Panel | Metric | Source |
|-------|--------|--------|
| CPU Usage | `ha_cpu_usage_millicores` | Pushgateway |
| Memory Usage | `ha_memory_usage_bytes / 1024 / 1024` | Pushgateway |
| Request Rate | `rate(nginx_http_requests_total[1m])` | nginx |
| Throughput | `sum(rate(nginx_http_requests_total[30s]))` | nginx |
| Active Connections | `nginx_connections_active` | nginx |

---

## Cleanup (When Done)

```bash
# Stop all port-forwards (Ctrl+C in each terminal)

# Delete K6 jobs
kubectl delete job k6-load-test k6-stress-test k6-spike-test k6-soak-test -n cse239fall2025 2>/dev/null || true

# Delete monitoring
cd monitoring
kubectl delete -f grafana.yaml -n cse239fall2025
kubectl delete -f grafana-datasources.yaml -n cse239fall2025
kubectl delete -f prometheus.yaml -n cse239fall2025
kubectl delete -f prometheus-config.yaml -n cse239fall2025
kubectl delete -f pushgateway-deployment.yaml -n cse239fall2025

# Delete application
helm uninstall dsb-socialnetwork -n cse239fall2025

# Verify cleanup
kubectl get pods -n cse239fall2025
```

---

## Quick Reference

| Service | Port-Forward | URL |
|---------|--------------|-----|
| Grafana | `kubectl port-forward svc/grafana 3000:3000 -n cse239fall2025` | http://localhost:3000 |
| Prometheus | `kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025` | http://localhost:9090 |
| Pushgateway | `kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025` | http://localhost:9091 |
| Application | `kubectl port-forward svc/nginx-thrift 8080:8080 -n cse239fall2025` | http://localhost:8080 |
