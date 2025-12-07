# Scripts - Load Testing & Metrics Collection

Scripts for load testing and metrics collection for the Social Network application.

---

## Files

### Metrics Collection

| File | Description |
|------|-------------|
| `push-metrics-loop.sh` | Continuously collects CPU/Memory and pushes to Pushgateway |

### K6 Load Tests

| File | Description |
|------|-------------|
| `k6-load-test.js` | Load test (100 users, 14 min) |
| `k6-stress-test.js` | Stress test (600 users, 15 min) |
| `k6-spike-test.js` | Spike test (500 users, 10 min) |
| `k6-soak-test.js` | Soak test (75 users, 30 min) |
| `k6-hpa-trigger-test.js` | HPA trigger test (800 users, 12 min) |

### K6 Kubernetes Jobs

| File | Description |
|------|-------------|
| `k6-configmap.yaml` | ConfigMap with load test script |
| `k6-job.yaml` | Job for load test |
| `k6-stress-job.yaml` | Job for stress test |
| `k6-spike-job.yaml` | Job for spike test |
| `k6-soak-job.yaml` | Job for soak test |
| `k6-hpa-trigger-job.yaml` | Job for HPA trigger test |

### Autoscaling

| File | Description |
|------|-------------|
| `nginx-hpa.yaml` | Horizontal Pod Autoscaler for nginx-thrift |

---

## Metrics Collection

### Prerequisites

Port-forward Pushgateway:
```bash
kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025
```

### Run Metrics Collector

```bash
./push-metrics-loop.sh 10
```

This collects CPU/Memory every 10 seconds for these 11 microservices:
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

### Metrics Pushed

| Metric | Description |
|--------|-------------|
| `ha_cpu_usage_millicores` | CPU usage in millicores |
| `ha_memory_usage_bytes` | Memory usage in bytes |

---

## Load Testing

### Run K6 Tests (In-Cluster)

```bash
# Deploy test scripts
kubectl apply -f k6-configmap.yaml -n cse239fall2025

# Run Load Test
kubectl apply -f k6-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-load-test

# Run Stress Test
kubectl delete job k6-load-test -n cse239fall2025 2>/dev/null || true
kubectl apply -f k6-stress-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test

# Run Spike Test
kubectl delete job k6-stress-test -n cse239fall2025 2>/dev/null || true
kubectl apply -f k6-spike-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-spike-test

# Run Soak Test
kubectl delete job k6-spike-test -n cse239fall2025 2>/dev/null || true
kubectl apply -f k6-soak-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-soak-test

# Run HPA Trigger Test
kubectl apply -f k6-hpa-trigger-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-hpa-trigger
```

### Test Summary

| Test | Duration | Max Users | Purpose |
|------|----------|-----------|---------|
| Load | 14 min | 100 | Baseline performance |
| Stress | 15 min | 600 | Find breaking point |
| Spike | 10 min | 500 | Traffic bursts |
| Soak | 30 min | 75 | Memory leak detection |
| HPA Trigger | 12 min | 800 | Trigger HPA scaling |

---

## Autoscaling (HPA)

```bash
# Apply HPA
kubectl apply -f nginx-hpa.yaml -n cse239fall2025

# Watch HPA
kubectl get hpa -n cse239fall2025 -w
```

HPA configured for nginx-thrift:
- Min replicas: 1
- Max replicas: 3
- CPU target: 30%
- Memory target: 70%

---

## Cleanup

```bash
# Delete K6 jobs
kubectl delete job k6-load-test k6-stress-test k6-spike-test k6-soak-test k6-hpa-trigger -n cse239fall2025 2>/dev/null || true

# Delete ConfigMaps
kubectl delete configmap k6-scripts k6-hpa-trigger-script -n cse239fall2025 2>/dev/null || true

# Delete HPA
kubectl delete -f nginx-hpa.yaml -n cse239fall2025 2>/dev/null || true
```
