# Commands Only

```bash
cd socialnetwork
helm install dsb-socialnetwork . -n cse239fall2025 --set global.prometheus.enabled=true
kubectl get pods -n cse239fall2025 -w
```

```bash
cd ../monitoring
kubectl apply -f prometheus-config.yaml -n cse239fall2025
kubectl apply -f prometheus.yaml -n cse239fall2025
kubectl apply -f pushgateway-deployment.yaml -n cse239fall2025
kubectl apply -f grafana-datasources.yaml -n cse239fall2025
kubectl apply -f grafana.yaml -n cse239fall2025
kubectl apply -f nginx-ingress.yaml -n cse239fall2025
kubectl get pods -n cse239fall2025 | grep -E "(prometheus|grafana|pushgateway)"
```

```bash
kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025
```

```bash
kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025
```

```
#Application: https://socialnetwork-haardhik.nrp-nautilus.io
#Grafana: https://grafana-haardhik.nrp-nautilus.io
#Dashboard: https://grafana-haardhik.nrp-nautilus.io/d/social-network-nautilus/social-network-nautilus-dashboard
```

```bash
cd ../scripts
./push-metrics-loop.sh 10
```

```bash
kubectl apply -f scripts/nginx-hpa.yaml -n cse239fall2025
kubectl get hpa -n cse239fall2025 -w
```

```bash
cd scripts
kubectl apply -f k6-configmap.yaml -n cse239fall2025
#Load Test
kubectl apply -f k6-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-load-test
kubectl delete job k6-load-test -n cse239fall2025 2>/dev/null || true
```

```bash
#Stress Test
kubectl apply -f k6-stress-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test
kubectl delete job k6-stress-test -n cse239fall2025 2>/dev/null || true
```

```bash
#Spike Test
kubectl apply -f k6-spike-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-spike-test
kubectl delete job k6-spike-test -n cse239fall2025 2>/dev/null || true
```

```bash
#Soak Test
kubectl apply -f k6-soak-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-soak-test
kubectl delete job k6-soak-test -n cse239fall2025 2>/dev/null || true
```

```bash
#Heavy load to trigger HPA
kubectl apply -f k6-hpa-trigger-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-hpa-trigger
kubectl delete job k6-hpa-trigger -n cse239fall2025 2>/dev/null || true
```

```bash
#Cleanup
kubectl delete job k6-load-test k6-stress-test k6-spike-test k6-soak-test k6-hpa-trigger -n cse239fall2025 2>/dev/null || true
kubectl delete configmap k6-scripts k6-hpa-trigger-script -n cse239fall2025 2>/dev/null || true
kubectl delete -f monitoring/nginx-ingress.yaml -n cse239fall2025
kubectl delete -f monitoring/grafana.yaml -n cse239fall2025
kubectl delete -f monitoring/grafana-datasources.yaml -n cse239fall2025
kubectl delete -f monitoring/prometheus.yaml -n cse239fall2025
kubectl delete -f monitoring/prometheus-config.yaml -n cse239fall2025
kubectl delete -f monitoring/pushgateway-deployment.yaml -n cse239fall2025
kubectl delete -f scripts/nginx-hpa.yaml -n cse239fall2025
helm uninstall dsb-socialnetwork -n cse239fall2025
kubectl get pods -n cse239fall2025
```
