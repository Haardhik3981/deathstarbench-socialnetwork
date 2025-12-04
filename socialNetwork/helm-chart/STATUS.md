# Project Status Summary

**Last Updated:** December 4, 2025

---

## ✅ What's Working

1. **K6 Load Testing Setup**
   - ✅ K6 runs inside cluster (k6-job.yaml)
   - ✅ Load test script configured (k6-load-test.js)
   - ✅ Stress test ready (k6-stress-job.yaml)
   - ✅ Spike test ready (k6-spike-job.yaml)
   - ✅ Soak test ready (k6-soak-job.yaml)

2. **Monitoring Stack**
   - ✅ Prometheus deployed and scraping
   - ✅ Grafana deployed with dashboards
   - ✅ 11 microservices have prometheus-exporter sidecars
   - ✅ kubectl top pods shows accurate resource usage

3. **Application Deployment**
   - ✅ Social network app deployed via Helm
   - ✅ nginx-thrift resource limits increased (2 CPU, 2Gi RAM)
   - ✅ All pods running with 2/2 containers (app + sidecar)

---

## ❌ What's NOT Working

### **Critical Issue: Grafana Metrics Don't Match kubectl top**

**Problem:**
- `kubectl top pods` shows: nginx 16m CPU = 0.016 cores
- Grafana shows: nginx 0.0012 cores (13x smaller!)
- Sidecar is reading container-level metrics, not pod-level

**Root Cause:**
- The prometheus-exporter sidecar reads from `/sys/fs/cgroup/cpu.stat`
- This gives only the sidecar's own CPU usage
- We need it to read the entire pod's CPU usage (nginx + sidecar combined)

**Attempted Fixes:**
1. ❌ Try reading from `../cpu.stat` (parent directory) - didn't work
2. ❌ Parse `/proc/self/cgroup` to find pod-level path - code not loading
3. ❌ Changed Grafana queries from `rate()` to instant - still wrong data source

**Why It's Hard:**
- Kubernetes cgroup v2 structure is complex
- Each container has its own cgroup
- Pod-level aggregation requires finding the correct parent cgroup path
- ConfigMap changes require pod deletion (not just restart) to take effect

---

## 🎯 What Needs to Be Fixed

### **Fix Priority 1: Pod-Level Metrics**

**Goal:** Make Grafana metrics match `kubectl top pods` exactly

**Approach Options:**

**Option A: Fix the Sidecar Script (Current Attempt)**
- Parse `/proc/self/cgroup` to find pod-level cgroup path
- Read CPU/Memory from pod-level path instead of container-level
- **Status:** Code written but not loading properly

**Option B: Use kubectl top Data Directly**
- Have sidecar query metrics-server API (same source as kubectl top)
- Requires RBAC permissions for sidecar
- More reliable but needs service account setup

**Option C: Use Kubelet Stats API**
- Query kubelet's `/stats/summary` endpoint
- Provides pod-level metrics directly
- Requires hostPath mount or node IP access

**Recommendation:** Option B (metrics-server API) is most reliable

---

## 📂 Important Files

### **Working Files:**
- `socialnetwork/` - Helm chart for social network app
- `monitoring/prometheus-configmap.yaml` - Prometheus scrape config (updated with nginx-thrift)
- `monitoring/grafana-dashboards-configmap.yaml` - Dashboard config (updated for instant queries)
- `monitoring/metrics-exporter-sidecar.yaml` - Sidecar script (needs fixing)
- `scripts/k6-*.js` - K6 test scripts (working)
- `scripts/k6-*-job.yaml` - K6 Kubernetes jobs (working)
- `QUICK-DEPLOY.md` - Deployment guide

### **Files to Keep:**
- `COMPLETE-TESTING-PLAN.md` - Complete K6 testing documentation

---

## 🚀 Quick Commands

### **Check Current State:**
```bash
# View actual resource usage
kubectl top pods -n cse239fall2025 | grep -E "nginx|compose|timeline"

# View what Grafana sees
kubectl port-forward -n cse239fall2025 $(kubectl get pods -n cse239fall2025 -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}') 9091:9091 &
curl -s http://localhost:9091/metrics | grep "pod_cpu_usage_cores"
pkill -f "port-forward.*9091"
```

### **Run Load Test:**
```bash
cd scripts/
kubectl apply -f k6-configmap.yaml -n cse239fall2025
kubectl apply -f k6-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-load-test
```

### **Access Monitoring:**
```bash
# Prometheus
kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025

# Grafana  
kubectl port-forward deployment/grafana 3000:3000 -n cse239fall2025
# Login: admin / admin
```

---

## 📋 Next Steps (For Tomorrow)

1. **Debug why sidecar code isn't loading:**
   - Check if ConfigMap is properly formatted (YAML indentation)
   - Verify Python syntax in the embedded script
   - Check pod logs for Python errors

2. **Alternative: Switch to metrics-server API approach:**
   - Create ServiceAccount with RBAC for sidecar
   - Modify sidecar to query metrics-server instead of cgroups
   - This will guarantee matching kubectl top values

3. **Test and validate:**
   - Run load test
   - Verify Grafana and kubectl top match
   - Document final solution

---

## 💡 Key Learnings

1. **kubectl top uses metrics-server**, not cgroups
2. **Sidecar reads cgroups**, which is why they differ
3. **For accurate pod-level metrics**, either:
   - Read pod-level cgroups (complex, cgroup v2 structure varies)
   - Query metrics-server API (reliable, same source as kubectl top)
4. **ConfigMap changes need pod deletion** to take effect (rollout restart isn't enough)
5. **nginx-thrift needs high resource limits** (2 CPU, 2Gi) for load testing

---

## 🎯 Success Criteria

The setup is complete when:
- ✅ K6 load test runs successfully (< 10% errors)
- ✅ Grafana metrics match kubectl top (within 10%)
- ✅ All 4 tests documented (load, stress, spike, soak)
- ✅ CPU/Memory increase visible in Grafana during tests

**Current Status:** 75% Complete
- K6 tests: ✅ Ready
- Monitoring stack: ✅ Deployed
- Metrics accuracy: ❌ Needs fixing
- Documentation: ✅ Complete

