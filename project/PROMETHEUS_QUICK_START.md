# Prometheus Quick Start - 5 Minutes

## Step 1: Access Prometheus

```bash
# Port-forward in a terminal (keep it running)
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Open in browser
open http://localhost:9090
```

## Step 2: Check Everything is Working

1. Click **Status > Targets** in the top menu
2. You should see targets with green "UP" status
3. **Don't worry** if endpoint links show "site can't be reached" - that's normal!

## Step 3: Try Your First Query

1. Click **Graph** in the top menu (or go to http://localhost:9090)
2. In the expression box, type:
   ```
   container_cpu_usage_seconds_total
   ```
3. Click **Execute**
4. See all CPU metrics for all containers!

## Step 4: Filter by Service

Try this query to see CPU for just user-service:
```
rate(container_cpu_usage_seconds_total{pod=~"user-service.*"}[5m]) * 100
```

This shows CPU usage as a percentage over 5-minute windows.

## Step 5: Try More Queries

**Memory usage:**
```
container_memory_usage_bytes{pod=~"user-service.*"} / 1024 / 1024
```
(Shows memory in MB)

**Network traffic:**
```
rate(container_network_receive_bytes_total[5m])
```

## Common Questions

**Q: Why do endpoint links show "site can't be reached"?**
A: Those are internal Kubernetes addresses. They only work from inside the cluster. Prometheus can access them - that's what matters! This is completely normal.

**Q: What do I actually do here?**
A: 
- Check Targets page: See if services are UP ✅
- Graph page: Query metrics to understand performance 📊
- Later: Create Grafana dashboards for visualization 📈

**Q: Where are my DeathStarBench services?**
A: They don't show in Targets because they use Thrift (not HTTP). But you can still monitor them with cAdvisor queries:
```
rate(container_cpu_usage_seconds_total{pod=~"user-service.*"}[5m])
```

## Next Steps

- Read `PROMETHEUS_GUIDE.md` for detailed explanations
- Create Grafana dashboards using these queries
- Monitor during k6 load tests

**That's it!** You're now using Prometheus. 🎉

