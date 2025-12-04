# Quick Deploy - All Commands in Order

Copy and paste these commands in order. Open 4 terminals.

## Terminal 1: Main Commands

### Step 1: Create Metrics Exporter ConfigMap
```bash
cd Helm/DeathStarBench/socialNetwork/helm-chart/monitoring
kubectl apply -f metrics-exporter-sidecar.yaml -n cse239fall2025
```

### Step 2: Deploy Application with Sidecars
```bash
cd ../socialnetwork

helm install dsb-socialnetwork . -n cse239fall2025 --set global.prometheus.enabled=true

# Watch pods come up (2/2 containers per pod)
kubectl get pods -n cse239fall2025 -w
# Press Ctrl+C when all show 2/2 Running
```

### Step 3: Port-Forward Application
Open Terminal 2:
```bash
kubectl port-forward deployment/nginx-thrift 8080:8080 -n cse239fall2025
# Keep this running
```

### Step 4: Deploy Monitoring (Back in Terminal 1)
```bash
cd ../monitoring

kubectl apply -f prometheus-configmap.yaml -n cse239fall2025
kubectl apply -f prometheus-deployment.yaml -n cse239fall2025
kubectl apply -f pushgateway-deployment.yaml -n cse239fall2025
kubectl apply -f grafana-dashboards-configmap.yaml -n cse239fall2025
kubectl apply -f grafana-deployment.yaml -n cse239fall2025

# Wait for monitoring to be ready
kubectl get pods -n cse239fall2025 | grep -E "(prometheus|grafana|pushgateway)"
```

**No Prometheus restart needed!** Prometheus will auto-discover the sidecars when it starts.

### Step 5: Port-Forward Prometheus and Grafana
Open Terminal 3:
```bash
kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025
# Keep this running
```

Open Terminal 4:
```bash
kubectl port-forward deployment/grafana 3000:3000 -n cse239fall2025
# Keep this running
```

### Step 6: Verify Everything Works

**Access Website:**
- Application: http://localhost:8080/

**Check Monitoring:**
- Prometheus: http://localhost:9090/targets (should show 10/10 UP)
- Grafana: http://localhost:3000 (login: admin/admin)

**Test Metrics in Prometheus:**
```promql
pod_cpu_usage_cores{namespace="cse239fall2025"}
pod_memory_usage_bytes{namespace="cse239fall2025"}
```

---

## Summary

You should now have:
- ✅ Monitoring stack running (Prometheus, Grafana, Pushgateway)
- ✅ Application running with sidecars (all pods 2/2)
- ✅ Metrics flowing from sidecars to Prometheus
- ✅ Dashboards in Grafana showing CPU, Memory, Pod Count

## Next Steps

### Run K6 Load Tests

```bash
cd scripts/

# Option 1: Run load test (14 min, 100 users)
kubectl apply -f k6-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-load-test

# Option 2: Run stress test (15 min, 600 users)
kubectl apply -f k6-stress-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test
```

### Set up HPA for Autoscaling

```bash
cd scripts/
kubectl apply -f hpa-config.yaml -n cse239fall2025
kubectl get hpa -n cse239fall2025 -w
```

---

## Step 7: Cleanup (Run This When Done Testing)

### 7.1 Uninstall Helm release
```bash
helm uninstall dsb-socialnetwork -n cse239fall2025
```

### 7.2 Delete monitoring stack
```bash
cd monitoring
kubectl delete -f grafana-deployment.yaml -n cse239fall2025
kubectl delete -f grafana-dashboards-configmap.yaml -n cse239fall2025
kubectl delete -f pushgateway-deployment.yaml -n cse239fall2025
kubectl delete -f prometheus-deployment.yaml -n cse239fall2025
kubectl delete -f prometheus-configmap.yaml -n cse239fall2025
kubectl delete -f metrics-exporter-sidecar.yaml -n cse239fall2025
```

### 7.3 Delete stuck/error pods (if any)
```bash
# Delete all pods in Error, Terminating, or ContainerStatusUnknown state
kubectl get pods -n cse239fall2025 | grep -E "(Error|ContainerStatusUnknown|Terminating)" | awk '{print $1}' | xargs -I {} kubectl delete pod {} -n cse239fall2025 --force --grace-period=0
```

### 7.4 Verify cleanup
```bash
kubectl get pods -n cse239fall2025
# Should show very few pods (only other users' pods)
```
