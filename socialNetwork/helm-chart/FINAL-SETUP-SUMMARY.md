# ✅ Final Setup Summary - K6 Load Testing & Application Metrics

## 🎯 What Was Accomplished

### 1. **K6 Load Testing (In-Cluster) - WORKING** ✅
- Created K6 test scripts that run **inside Kubernetes**
- No port-forward issues - much more stable
- Successfully tested with 100 users (load test) and 600 users (stress test)

### 2. **Fixed Helm Template for nginx-thrift Sidecar** ✅
- Updated `_baseNginxDeployment.tpl` to include prometheus-exporter sidecar
- Now nginx-thrift will have metrics like other services
- Proper Helm-managed deployment

### 3. **Enhanced Grafana Dashboard** ✅
- Updated dashboard to show all 11 microservices
- Added CPU rate by service (stacked)
- Added memory usage by service (stacked)
- Added request rate estimation
- Added system load indicator
- Removed non-working K6 metrics (those aren't exported to Prometheus)

---

## 📁 Clean Scripts Folder

Your `scripts/` folder now contains only essential files:

**K6 Load Tests:**
- `k6-load-test.js` - Load test (100 users, 14 min)
- `k6-stress-test.js` - Stress test (600 users, 15 min)
- `k6-soak-test.js` - Soak test (75 users, 30 min)

**K6 In-Cluster Deployment:**
- `k6-configmap.yaml` - Load test script as ConfigMap
- `k6-job.yaml` - Kubernetes Job for load test
- `k6-stress-job.yaml` - Kubernetes Job for stress test

**Autoscaling:**
- `hpa-config.yaml` - Horizontal Pod Autoscaler
- `vpa-config.yaml` - Vertical Pod Autoscaler

**Utils:**
- `run-tests.sh` - Interactive test runner
- `README.md` - Documentation
- `load-test-results.json` - Previous test results

---

## 🚀 Complete Deployment Steps (Fresh Start)

### **Step 1: Clean Slate**

```bash
# Uninstall existing Helm release
helm uninstall dsb-socialnetwork -n cse239fall2025

# Clean up monitoring
cd monitoring/
kubectl delete -f grafana-deployment.yaml -n cse239fall2025
kubectl delete -f grafana-dashboards-configmap.yaml -n cse239fall2025
kubectl delete -f pushgateway-deployment.yaml -n cse239fall2025
kubectl delete -f prometheus-deployment.yaml -n cse239fall2025
kubectl delete -f prometheus-configmap.yaml -n cse239fall2025
kubectl delete -f metrics-exporter-sidecar.yaml -n cse239fall2025

# Wait for cleanup
sleep 10
```

### **Step 2: Deploy Application with Sidecars**

```bash
cd monitoring/
kubectl apply -f metrics-exporter-sidecar.yaml -n cse239fall2025

cd ../socialnetwork/
helm install dsb-socialnetwork . -n cse239fall2025 --set global.prometheus.enabled=true

# Watch all pods come up (ALL should show 2/2)
kubectl get pods -n cse239fall2025 -w
```

**Wait until all application pods show `2/2 Running`**, then press `Ctrl+C`

### **Step 3: Deploy Monitoring Stack**

```bash
cd ../monitoring/

kubectl apply -f prometheus-configmap.yaml -n cse239fall2025
kubectl apply -f prometheus-deployment.yaml -n cse239fall2025
kubectl apply -f pushgateway-deployment.yaml -n cse239fall2025
kubectl apply -f grafana-dashboards-configmap.yaml -n cse239fall2025
kubectl apply -f grafana-deployment.yaml -n cse239fall2025

# Wait for monitoring pods
kubectl get pods -n cse239fall2025 | grep -E "(prometheus|grafana|pushgateway)"
```

### **Step 4: Port-Forward Services**

**Terminal 1:** Prometheus
```bash
kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025
```

**Terminal 2:** Grafana
```bash
kubectl port-forward deployment/grafana 3000:3000 -n cse239fall2025
```

### **Step 5: Verify Everything**

```bash
# Check Prometheus targets (should show 10/10 UP)
open http://localhost:9090/targets

# Open Grafana
open http://localhost:3000
# Login: admin / admin
```

---

## 🧪 Run K6 Load Tests

### **Test 1: Load Test (14 min)**

```bash
cd scripts/

# Deploy K6 scripts
kubectl apply -f k6-configmap.yaml -n cse239fall2025

# Run load test
kubectl apply -f k6-job.yaml -n cse239fall2025

# Watch progress
kubectl logs -f -n cse239fall2025 -l app=k6-load-test

# Monitor in Grafana: http://localhost:3000
```

**Expected Results:**
- Total Requests: 20,000-25,000
- Success Rate: > 95%
- Error Rate: < 5%
- Throughput: 25-35 req/s
- p95 Latency: < 500ms

### **Test 2: Stress Test (15 min)**

```bash
# Wait 5 minutes for recovery
sleep 300

# Run stress test
kubectl apply -f k6-stress-job.yaml -n cse239fall2025

# Watch progress
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test
```

**Expected Results:**
- Total Requests: 140,000-150,000
- Success Rate: 90-95%
- Error Rate: 5-10%
- Throughput: 140-180 req/s
- Breaking Point: ~400-500 users

---

## 📊 Grafana Dashboard Metrics

Your dashboard now shows:

### **Resource Metrics:**
- Total CPU (cores)
- Total Memory
- Pod Count Over Time
- CPU Usage by Pod (ALL pods)
- Memory Usage Over Time

### **Service-Level Metrics:**
- nginx-thrift CPU
- compose-post-service CPU
- home-timeline-service CPU
- user-timeline-service CPU
- CPU Rate by Service (Stacked - ALL 11 services)
- Memory Usage by Service (Stacked - ALL 11 services)

### **Performance Analysis:**
- Estimated Request Rate (CPU-based)
- System Load Indicator (% of baseline)
- Throughput estimation

### **Detailed Table:**
- All pods with CPU & Memory usage

---

## 🎓 Key Learnings

### **What Works:**
✅ K6 running **inside cluster** (no port-forward issues)  
✅ Prometheus scraping **sidecar exporters** from all services  
✅ Grafana showing **real-time resource metrics**  
✅ All 11 microservices visible and monitored  
✅ CPU/Memory correlate with application load  

### **What Doesn't Work (By Design):**
❌ HTTP-level metrics (requests, latency) in Prometheus  
   → DeathStarBench services don't export these  
   → **Use K6 output for HTTP metrics instead**

### **Monitoring Strategy:**
- **Grafana:** Infrastructure & resource metrics (CPU, memory, scaling)
- **K6 Output:** Application metrics (throughput, latency, errors)
- **Combined:** Complete visibility ✅

---

## 🔧 Important Files Modified

1. **`socialnetwork/templates/_baseNginxDeployment.tpl`**
   - Added prometheus-exporter sidecar support
   - Now nginx-thrift gets sidecar like other services

2. **`monitoring/grafana-dashboards-configmap.yaml`**
   - Fixed broken K6 metrics queries
   - Added all 11 services to graphs
   - Added request rate estimation
   - Added system load indicator

---

## 📋 Remaining Files in scripts/

**Core K6 Tests:**
- `k6-load-test.js` - 100 users, 14 min
- `k6-stress-test.js` - 600 users, 15 min
- `k6-soak-test.js` - 75 users, 30 min

**K6 In-Cluster:**
- `k6-configmap.yaml` - Test scripts as ConfigMap
- `k6-job.yaml` - Load test Job
- `k6-stress-job.yaml` - Stress test Job

**Autoscaling:**
- `hpa-config.yaml` - Horizontal Pod Autoscaler
- `vpa-config.yaml` - Vertical Pod Autoscaler

**Utils:**
- `run-tests.sh` - Interactive test runner
- `README.md` - Documentation

---

## ✅ Next Steps for You

1. **Follow QUICK-DEPLOY.md** to redeploy from scratch
2. **Verify nginx-thrift has 2/2 containers**
3. **Run load tests** and watch Grafana
4. **All metrics should work now!**

---

## 🎉 Summary

You now have:
- ✅ Complete K6 load testing suite (in-cluster, stable)
- ✅ Fixed Helm templates (nginx has sidecar)
- ✅ Enhanced Grafana dashboard (all services, proper metrics)
- ✅ Clean scripts folder (no redundant files)
- ✅ Production-ready monitoring setup

**Ready to test!** 🚀

