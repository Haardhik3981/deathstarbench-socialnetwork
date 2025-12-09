# Monitoring Stack for Social Network (Nautilus)

Prometheus + Grafana monitoring for the DeathStarBench Social Network application on Nautilus Kubernetes cluster.

---

## Quick Start

See **[COMMANDS-ONLY.md](./COMMANDS-ONLY.md)** for step-by-step deployment commands.

---

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   nginx-thrift  │     │   Pushgateway   │     │    Prometheus   │
│   :9091/metrics │────▶│   :9091         │◀────│   :9090         │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                              ▲                          │
                              │                          ▼
                    ┌─────────┴─────────┐       ┌─────────────────┐
                    │ push-metrics-loop │       │     Grafana     │
                    │   (kubectl top)   │       │     :3000       │
                    └───────────────────┘       └─────────────────┘
```

---

## Files

| File | Description |
|------|-------------|
| `prometheus-config.yaml` | Prometheus scrape configuration |
| `prometheus.yaml` | Prometheus Deployment + Service |
| `grafana.yaml` | Grafana Deployment + Service + Ingress |
| `grafana-datasources.yaml` | Prometheus datasource for Grafana |
| `grafana-dashboard.json` | Pre-built dashboard to import |
| `pushgateway-deployment.yaml` | Pushgateway for CPU/Memory metrics |
| `nginx-ingress.yaml` | Ingress for nginx-thrift external access |
| `COMMANDS-ONLY.md` | Commands-only deployment reference |

---

## Available Metrics

### From nginx (real-time)
- `nginx_http_requests_total` - Total HTTP requests
- `nginx_connections_active` - Active connections

### From Pushgateway (via push-metrics-loop.sh)
- `ha_cpu_usage_millicores` - CPU usage per pod
- `ha_memory_usage_bytes` - Memory usage per pod

---

## Dashboard Panels

The `grafana-dashboard.json` includes:

**Resource Metrics:**
- CPU Usage (millicores) - time series
- Memory Usage (MiB) - time series
- Total CPU / Memory - stat panels
- CPU by Pod (Stacked) - area chart
- Resource Table - with gauges

**Traffic Metrics:**
- Request Rate (RPS)
- Throughput (Requests/sec)
- Active Connections
- Total Requests

---

## Deployment

```bash
# Deploy monitoring
kubectl apply -f prometheus-config.yaml -n cse239fall2025
kubectl apply -f prometheus.yaml -n cse239fall2025
kubectl apply -f pushgateway-deployment.yaml -n cse239fall2025
kubectl apply -f grafana-datasources.yaml -n cse239fall2025
kubectl apply -f grafana.yaml -n cse239fall2025
kubectl apply -f nginx-ingress.yaml -n cse239fall2025

# Port-forward (Prometheus and Pushgateway)
kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025
kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025

# Start metrics collector (in scripts folder)
./push-metrics-loop.sh 10
```

## Access (Global)

- **Application:** https://socialnetwork-haardhik.nrp-nautilus.io
- **Grafana:** https://grafana-haardhik.nrp-nautilus.io
- **Dashboard:** https://grafana-haardhik.nrp-nautilus.io/d/social-network-nautilus/social-network-nautilus-dashboard
- **Login:** `admin` / `admin`

---

## Nautilus Limitations

This setup works within Nautilus restrictions:
- ❌ No RBAC/ServiceMonitor (not allowed)
- ❌ No kubelet/cAdvisor metrics (blocked)
- ✅ Static targets only
- ✅ Pushgateway for custom metrics
- ✅ nginx-exporter for HTTP metrics
