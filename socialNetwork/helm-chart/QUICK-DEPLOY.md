# Quick Deploy Guide

Namespace: `cse239fall2025`

---

## 1. Deploy Application

```bash
cd socialnetwork
helm install dsb-socialnetwork . -n cse239fall2025 --set global.prometheus.enabled=true
kubectl get pods -n cse239fall2025 -w
```

---

## 2. Deploy Monitoring Stack

```bash
cd ../monitoring
kubectl apply -f prometheus-config.yaml -n cse239fall2025
kubectl apply -f prometheus.yaml -n cse239fall2025
kubectl apply -f pushgateway-deployment.yaml -n cse239fall2025
kubectl apply -f grafana-datasources.yaml -n cse239fall2025
kubectl apply -f grafana.yaml -n cse239fall2025
kubectl apply -f nginx-ingress.yaml -n cse239fall2025
```

---

## 3. Port-Forward Services

| Service | Command |
|---------|---------|
| Prometheus | `kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025` |
| Pushgateway | `kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025` |

---

## 4. Start Metrics Collector

```bash
cd ../scripts
./push-metrics-loop.sh 10
```

---

## 5. Access Grafana Dashboard

**URL:** https://grafana-haardhik.nrp-nautilus.io

**Dashboard:** https://grafana-haardhik.nrp-nautilus.io/d/social-network-nautilus/social-network-nautilus-dashboard

**Login:** `admin` / `admin`

To import dashboard (if needed):
1. Dashboards → Import → Upload `monitoring/grafana-dashboard.json`

---

## 6. Apply HPA (nginx-thrift)

```bash
kubectl apply -f scripts/nginx-hpa.yaml -n cse239fall2025
kubectl get hpa -n cse239fall2025 -w
```

---

## 7. Run Load Tests

```bash
cd scripts
kubectl apply -f k6-configmap.yaml -n cse239fall2025

# Load Test
kubectl apply -f k6-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-load-test

# Stress Test
kubectl apply -f k6-stress-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test

# HPA Trigger Test
kubectl apply -f k6-hpa-trigger-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-hpa-trigger
```

---

## 8. Cleanup

```bash
# Delete K6 jobs
kubectl delete job k6-load-test k6-stress-test k6-spike-test k6-soak-test k6-hpa-trigger -n cse239fall2025 2>/dev/null || true

# Delete monitoring
kubectl delete -f monitoring/nginx-ingress.yaml -n cse239fall2025
kubectl delete -f monitoring/grafana.yaml -n cse239fall2025
kubectl delete -f monitoring/grafana-datasources.yaml -n cse239fall2025
kubectl delete -f monitoring/prometheus.yaml -n cse239fall2025
kubectl delete -f monitoring/prometheus-config.yaml -n cse239fall2025
kubectl delete -f monitoring/pushgateway-deployment.yaml -n cse239fall2025

# Delete HPA
kubectl delete -f scripts/nginx-hpa.yaml -n cse239fall2025

# Delete application
helm uninstall dsb-socialnetwork -n cse239fall2025
```

---

## Access URLs (Global)

| Service | URL |
|---------|-----|
| Social Network App | https://socialnetwork-haardhik.nrp-nautilus.io |
| Grafana Dashboard | https://grafana-haardhik.nrp-nautilus.io/d/social-network-nautilus/social-network-nautilus-dashboard |
| Prometheus | http://localhost:9090 (port-forward) |
| Pushgateway | http://localhost:9091 (port-forward) |

---

## API Endpoints

| Endpoint | URL |
|----------|-----|
| Home Timeline | `https://socialnetwork-haardhik.nrp-nautilus.io/wrk2-api/home-timeline/read?user_id=1&start=0&stop=10` |
| User Timeline | `https://socialnetwork-haardhik.nrp-nautilus.io/wrk2-api/user-timeline/read?user_id=1&start=0&stop=10` |
| Compose Post | `https://socialnetwork-haardhik.nrp-nautilus.io/wrk2-api/post/compose` |
| Register User | `https://socialnetwork-haardhik.nrp-nautilus.io/wrk2-api/user/register` |
| Follow User | `https://socialnetwork-haardhik.nrp-nautilus.io/wrk2-api/user/follow` |
