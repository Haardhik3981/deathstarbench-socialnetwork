# DeathStarBench Social Network - Nautilus Monitoring Setup

**Prometheus + Grafana monitoring for Kubernetes (Nautilus cluster)**

This directory contains a complete, Nautilus-compatible monitoring stack for the DeathStarBench Social Network application.

---

## 🚀 Quick Start

**Start here:**

1. **[COMMANDS-ONLY.md](./COMMANDS-ONLY.md)** - All commands from scratch (recommended)
2. **[YES-WE-CAN-DO-THIS.md](./YES-WE-CAN-DO-THIS.md)** - Can we do latency/CPU/memory? (yes!)
3. **[PERFORMANCE-DASHBOARD.md](./PERFORMANCE-DASHBOARD.md)** - Performance analysis guide

---

## 📚 Documentation

| File | When to Read |
|------|--------------|
| **[COMMANDS-ONLY.md](./COMMANDS-ONLY.md)** | ⚡ **START HERE** - All commands from cleanup to metrics |
| **[YES-WE-CAN-DO-THIS.md](./YES-WE-CAN-DO-THIS.md)** | ✅ Can we do latency/CPU/memory? Quick answers |
| **[PERFORMANCE-DASHBOARD.md](./PERFORMANCE-DASHBOARD.md)** | 📊 Complete performance analysis guide |
| **[GRAFANA-TEST-QUERIES.md](./GRAFANA-TEST-QUERIES.md)** | 📋 15+ queries to test in Grafana |

---

## 📁 Deployment Files

| File | Description | Edit Required? |
|------|-------------|----------------|
| `prometheus-config.yaml` | Prometheus ConfigMap with static targets | ❌ No |
| `prometheus.yaml` | Prometheus Deployment + Service | ❌ No |
| `grafana-datasources.yaml` | Grafana datasource pointing to Prometheus | ❌ No |
| `grafana.yaml` | Grafana Deployment + Service + Ingress | ✅ **YES - Change hostname!** |
| `pushgateway-deployment.yaml` | Pushgateway for k6/kubectl top metrics | ❌ No |

---

## ✅ What This Setup Does

- ✅ Deploys Prometheus in your namespace (static targets - no RBAC needed)
- ✅ Deploys Grafana with external Ingress
- ✅ **Instruments nginx-thrift frontend with Prometheus metrics** (HTTP requests, connections, etc.)
- ✅ Works within Nautilus restrictions (no Role/ClusterRole needed!)
- ✅ Pre-configures Prometheus datasource in Grafana
- ✅ Optional Pushgateway for batch job metrics

---

## ❌ What This Setup Does NOT Do

- ❌ Node-level metrics (kubelet API blocked on Nautilus)
- ❌ RBAC/ServiceMonitor (Role creation forbidden on Nautilus)
- ❌ Kubernetes service discovery (requires RBAC - not allowed)
- ❌ Pod-level CPU/memory from kubelet (blocked on Nautilus)
- ❌ Metrics from other microservices (only nginx-thrift is instrumented)

**Note:** Only nginx-thrift has the metrics exporter sidecar. Other services run 1/1 (no sidecars).

---

## 🎯 Typical Workflow

```bash
# 1. Deploy application + monitoring
cd DeathStarBench/socialNetwork/helm-chart
./monitoring/COMMANDS-ONLY.sh

# 2. Access Grafana
# https://grafana-YOURNAME.nrp-nautilus.io (admin/admin)

# 3. Verify Prometheus datasource is connected
# Go to: Configuration → Data Sources → Prometheus

# 4. (Optional) Instrument services for metrics
# See NAUTILUS-SETUP.md

# 5. Create dashboards
# + → Dashboard → Add visualization

# 6. Run load tests and watch metrics
cd scripts
kubectl apply -f k6-job.yaml -n cse239fall2025
```

---

## 🔧 Required Configuration

**Before deploying, you MUST edit `grafana.yaml`:**

```bash
vim grafana.yaml

# Change this line (appears twice):
  host: grafana-haardhik.nrp-nautilus.io
# To something unique like:
  host: grafana-yourname.nrp-nautilus.io
```

Or use sed:
```bash
sed -i 's/grafana-haardhik/grafana-yourname/g' grafana.yaml
```

---

## 🌟 Key Features

### Static Target Configuration
- No RBAC needed (Nautilus doesn't allow Role creation)
- Direct DNS-based scraping
- Works without any permissions

### Simple Architecture
```
nginx-thrift (port 9091)
        ↓ (static target: nginx-thrift:9091)
   PROMETHEUS
        ↓ (http://prometheus:9090)
    GRAFANA
        ↓ (HAProxy Ingress)
   External Access
```

### Nautilus-Compatible
- Works within Nautilus restrictions (no RBAC allowed)
- Static targets (no service discovery)
- Uses emptyDir for storage (no PVC issues)
- HAProxy Ingress for external access

---

## 📊 What You'll See

### Immediately After Deployment

**In Prometheus** (`http://localhost:9090/targets`):
- ✅ Prometheus itself (UP)
- ✅ nginx-frontend (UP) - nginx-thrift metrics
- ✅ pushgateway (UP) - if deployed

**In Grafana** (`https://grafana-yourname.nrp-nautilus.io`):
- ✅ Prometheus datasource connected
- ✅ Nginx metrics available!
- ✅ Ready to create dashboards

### After Creating Dashboards

- ✅ Real-time HTTP request metrics
- ✅ Connection monitoring
- ✅ Traffic visualization during load tests
- ✅ Performance tracking

---

## 🆘 Quick Troubleshooting

```bash
# Check all pods
kubectl get pods -n cse239fall2025

# Check monitoring logs
kubectl logs -n cse239fall2025 -l app=prometheus --tail=50
kubectl logs -n cse239fall2025 -l app=grafana --tail=50

# Test Prometheus from Grafana
GRAFANA_POD=$(kubectl get pods -n cse239fall2025 -l app=grafana -o name | head -1)
kubectl exec -n cse239fall2025 $GRAFANA_POD -- wget -O- http://prometheus:9090/-/healthy

# Check Ingress
kubectl describe ingress grafana-ingress -n cse239fall2025

# Port-forward if Ingress doesn't work
kubectl port-forward -n cse239fall2025 svc/grafana 3000:3000
```

**For more troubleshooting, see QUICKSTART.md → "Troubleshooting" section**

---

## 🧹 Cleanup

```bash
# Quick cleanup
helm uninstall dsb-socialnetwork -n cse239fall2025
kubectl delete -f monitoring/grafana.yaml
kubectl delete -f monitoring/grafana-datasources.yaml
kubectl delete -f monitoring/prometheus.yaml
kubectl delete -f monitoring/prometheus-config.yaml

# Or see CHEATSHEET.md → "Cleanup Everything"
```

---

## 📖 Next Steps

1. ✅ Deploy monitoring stack
2. ✅ Verify Grafana is accessible
3. ✅ Check Prometheus datasource
4. 📊 Test queries (see GRAFANA-TEST-QUERIES.md)
5. 📊 Create your first dashboard
6. 🚀 Run load tests and watch metrics
7. 📈 Set up alerts (optional)

---

## 🎓 Learning Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Tutorials](https://grafana.com/tutorials/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Nautilus Documentation](https://ucsd-prp.gitlab.io/)

---

## 💡 Tips

1. **Start simple**: Deploy monitoring first, instrument services later
2. **Use port-forward**: Test locally before exposing via Ingress
3. **Check logs**: Most issues show up in pod logs
4. **Instrument gradually**: Start with nginx-thrift, add more services later
5. **Save dashboards**: Export JSON and commit to git

---

## 🤝 Contributing

Found an issue? Have improvements?
- Open an issue
- Submit a PR
- Update documentation

---

## 📋 Checklist

Before deployment:
- [ ] Kubectl configured for Nautilus
- [ ] Namespace `cse239fall2025` exists
- [ ] Edited `grafana.yaml` hostname
- [ ] Application deployed (or ready to deploy)

After deployment:
- [ ] All pods Running
- [ ] Grafana accessible via Ingress
- [ ] Prometheus datasource connected
- [ ] Queries return results in Grafana

---

**Ready to start?** Pick a guide from the top and follow along! 🚀

**Questions?** See [NAUTILUS-SETUP.md](./NAUTILUS-SETUP.md) for comprehensive documentation.

