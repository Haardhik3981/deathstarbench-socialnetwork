# Commands Only - Start from Scratch

**Copy-paste these commands in order. No explanations, just commands.**

---

## Step 1: Cleanup

```bash
cd /Users/haardhikmudagereanil/Downloads/MSCS\ -\ UCSC/Q4/CSE239_AdvCloudComputing/Project/DeathStarBench_project_root/DeathStarBench/socialNetwork/helm-chart

helm uninstall dsb-socialnetwork -n cse239fall2025 2>/dev/null || true

kubectl delete -f monitoring/grafana.yaml -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/grafana-datasources.yaml -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/prometheus.yaml -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/prometheus-config.yaml -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/pushgateway-deployment.yaml -n cse239fall2025 2>/dev/null || true

kubectl get pods -n cse239fall2025 --no-headers | grep -E "(Error|Terminating)" | awk '{print $1}' | xargs -I {} kubectl delete pod {} -n cse239fall2025 --force --grace-period=0 2>/dev/null || true

kubectl get pods -n cse239fall2025
```

---

## Step 2: Deploy Application

```bash
cd socialnetwork

helm install dsb-socialnetwork . -n cse239fall2025 --set global.prometheus.enabled=true

sleep 30
kubectl get pods -n cse239fall2025 -w
# Press Ctrl+C when all Running
```

---

## Step 3: Edit Grafana Hostname

```bash
cd ../monitoring

# EDIT THIS: Replace YOURNAME with your actual name
#sed -i '' 's/grafana-haardhik/grafana-YOURNAME/g' grafana.yaml

# Or edit manually:
# vim grafana.yaml
# Change: grafana-haardhik.nrp-nautilus.io
# To: grafana-YOURNAME.nrp-nautilus.io
```

---

## Step 4: Deploy Monitoring

```bash
kubectl apply -f prometheus-config.yaml
kubectl apply -f prometheus.yaml
kubectl apply -f grafana-datasources.yaml
kubectl apply -f grafana.yaml
kubectl apply -f pushgateway-deployment.yaml

#kubectl wait --for=condition=ready pod -l app=prometheus -n cse239fall2025 --timeout=120s
#kubectl wait --for=condition=ready pod -l app=grafana -n cse239fall2025 --timeout=120s

kubectl get pods -n cse239fall2025 | grep -E "(prometheus|grafana|pushgateway)"
#kubectl get ingress grafana-ingress -n cse239fall2025: grafana-haardhik.nrp-nautilus.io
```

---

## Step 5: Access Grafana

```bash
# Get Grafana URL
kubectl get ingress grafana-ingress -n cse239fall2025 -o jsonpath='{.spec.rules[0].host}' && echo

# Open in browser: https://grafana-YOURNAME.nrp-nautilus.io
# Login: admin / admin
```

---

## Step 6: Verify Prometheus Targets

```bash
# Port-forward Prometheus (Terminal 1)
kubectl port-forward -n cse239fall2025 svc/prometheus 9090:9090

# Open: http://localhost:9090/targets
# Should see:
# - prometheus (UP)
# - nginx-frontend (UP)
# - pushgateway (UP)
```

---

## Step 7: Test Metrics in Grafana

```
Go to Grafana → Explore

Query 1: up{job="nginx-frontend"}
Expected: 1

Query 2: nginx_http_requests_total
Expected: a number

Query 3: rate(nginx_http_requests_total[1m])
Expected: 0.0 or higher

Query 4: nginx_connections_active
Expected: 1-10
```

---

## Step 8: Generate Test Traffic

```bash
# Terminal 1: Port-forward nginx
kubectl port-forward -n cse239fall2025 deployment/nginx-thrift 8080:8080 &

# Terminal 2: Generate requests
for i in {1..100}; do curl -s http://localhost:8080/ > /dev/null; echo "Request $i"; sleep 0.1; done

# In Grafana, query this and watch it spike:
# rate(nginx_http_requests_total[30s])

pkill -f "port-forward.*8080"
```

---

## Step 9: Create Dashboard

```
In Grafana:

1. Click + → Dashboard
2. Add visualization
3. Query: rate(nginx_http_requests_total[1m])
4. Title: Request Rate
5. Apply
6. Save dashboard as: "Social Network Performance"
```

---

## Step 10: Run Stress Test

```bash
cd ../scripts

kubectl apply -f k6-configmap.yaml -n cse239fall2025
kubectl apply -f k6-stress-job.yaml -n cse239fall2025

# Watch logs
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test

# While test runs, watch Grafana dashboard!
```

---

## Step 11: Extract Latency and CPU/Memory Metrics (After Test)

```bash
cd scripts

# Extract latency, CPU, and memory metrics from k6 logs
bash push-k6-metrics.sh

# Collect current CPU/memory using kubectl top
bash collect-resource-metrics.sh
```

---

## Step 12: Query Performance Metrics in Grafana

```
Query these in Grafana Explore:

Latency:
- k6_latency_avg_ms{job="k6-stress-test"}
- k6_latency_p95_ms{job="k6-stress-test"}
- k6_latency_p99_ms{job="k6-stress-test"}

CPU/Memory:
- pod_cpu_usage_cores{pod=~".*service.*"}
- pod_memory_usage_bytes{pod=~".*service.*"}

Request Rate:
- rate(nginx_http_requests_total[1m])
```

---

## Cleanup (When Done)

```bash
cd monitoring

helm uninstall dsb-socialnetwork -n cse239fall2025
kubectl delete -f grafana.yaml
kubectl delete -f grafana-datasources.yaml
kubectl delete -f prometheus.yaml
kubectl delete -f prometheus-config.yaml
kubectl delete -f pushgateway-deployment.yaml

kubectl get pods -n cse239fall2025
```

---

**That's it! All commands in order from cleanup to performance analysis.**

