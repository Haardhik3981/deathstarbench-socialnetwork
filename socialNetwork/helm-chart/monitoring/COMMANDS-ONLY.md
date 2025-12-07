# Commands Only

```bash
cd socialnetwork                                                                  # Navigate to helm chart directory
helm install dsb-socialnetwork . -n cse239fall2025 --set global.prometheus.enabled=true  # Deploy Social Network app with Prometheus enabled
kubectl get pods -n cse239fall2025 -w                                             # Watch pods until all are Running
```

```bash
cd ../monitoring                                                                  # Navigate to monitoring directory
kubectl apply -f prometheus-config.yaml -n cse239fall2025                         # Deploy Prometheus ConfigMap (scrape targets)
kubectl apply -f prometheus.yaml -n cse239fall2025                                # Deploy Prometheus server
kubectl apply -f pushgateway-deployment.yaml -n cse239fall2025                    # Deploy Pushgateway for custom metrics
kubectl apply -f grafana-datasources.yaml -n cse239fall2025                       # Deploy Grafana datasource ConfigMap
kubectl apply -f grafana.yaml -n cse239fall2025                                   # Deploy Grafana with Ingress
kubectl apply -f nginx-ingress.yaml -n cse239fall2025                             # Deploy Ingress for external app access
kubectl get pods -n cse239fall2025 | grep -E "(prometheus|grafana|pushgateway)"   # Verify monitoring pods are running
```

```bash
kubectl port-forward svc/prometheus 9090:9090 -n cse239fall2025                   # Port-forward Prometheus to localhost:9090
```

```bash
kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025                  # Port-forward Pushgateway to localhost:9091
```

```
# Application: https://socialnetwork-haardhik.nrp-nautilus.io                     # Global URL for Social Network app
# Grafana: https://grafana-haardhik.nrp-nautilus.io                               # Global URL for Grafana
# Dashboard: https://grafana-haardhik.nrp-nautilus.io/d/social-network-nautilus/social-network-nautilus-dashboard  # Direct dashboard link
```

```bash
cd ../scripts                                                                     # Navigate to scripts directory
./push-metrics-loop.sh 10                                                         # Start metrics collector (pushes CPU/Memory every 10s)
```

```bash
kubectl apply -f scripts/nginx-hpa.yaml -n cse239fall2025                         # Deploy HPA for nginx-thrift autoscaling
kubectl get hpa -n cse239fall2025 -w                                              # Watch HPA status and scaling events
```

```bash
cd scripts                                                                        # Navigate to scripts directory
kubectl apply -f k6-configmap.yaml -n cse239fall2025                              # Deploy K6 test scripts ConfigMap
# Load Test
kubectl apply -f k6-job.yaml -n cse239fall2025                                    # Run load test (100 users, 14 min)
kubectl logs -f -n cse239fall2025 -l app=k6-load-test                             # Stream load test logs
kubectl delete job k6-load-test -n cse239fall2025 2>/dev/null || true             # Cleanup load test job
```

```bash
# Stress Test
kubectl apply -f k6-stress-job.yaml -n cse239fall2025                             # Run stress test (600 users, 15 min)
kubectl logs -f -n cse239fall2025 -l app=k6-stress-test                           # Stream stress test logs
kubectl delete job k6-stress-test -n cse239fall2025 2>/dev/null || true           # Cleanup stress test job
```

```bash
# Spike Test
kubectl apply -f k6-spike-job.yaml -n cse239fall2025                              # Run spike test (500 users, 10 min)
kubectl logs -f -n cse239fall2025 -l app=k6-spike-test                            # Stream spike test logs
kubectl delete job k6-spike-test -n cse239fall2025 2>/dev/null || true            # Cleanup spike test job
```

```bash
# Soak Test
kubectl apply -f k6-soak-job.yaml -n cse239fall2025                               # Run soak test (75 users, 30 min)
kubectl logs -f -n cse239fall2025 -l app=k6-soak-test                             # Stream soak test logs
kubectl delete job k6-soak-test -n cse239fall2025 2>/dev/null || true             # Cleanup soak test job
```

```bash
# Heavy load to trigger HPA
kubectl apply -f k6-hpa-trigger-job.yaml -n cse239fall2025                        # Run HPA trigger test (800 users, 12 min)
kubectl logs -f -n cse239fall2025 -l app=k6-hpa-trigger                           # Stream HPA trigger test logs
kubectl delete job k6-hpa-trigger -n cse239fall2025 2>/dev/null || true           # Cleanup HPA trigger job
```

```bash
# Cleanup
kubectl delete job k6-load-test k6-stress-test k6-spike-test k6-soak-test k6-hpa-trigger -n cse239fall2025 2>/dev/null || true  # Delete all K6 jobs
kubectl delete configmap k6-scripts k6-hpa-trigger-script -n cse239fall2025 2>/dev/null || true  # Delete K6 ConfigMaps
kubectl delete -f monitoring/nginx-ingress.yaml -n cse239fall2025                 # Delete app Ingress
kubectl delete -f monitoring/grafana.yaml -n cse239fall2025                       # Delete Grafana
kubectl delete -f monitoring/grafana-datasources.yaml -n cse239fall2025           # Delete Grafana datasource
kubectl delete -f monitoring/prometheus.yaml -n cse239fall2025                    # Delete Prometheus
kubectl delete -f monitoring/prometheus-config.yaml -n cse239fall2025             # Delete Prometheus ConfigMap
kubectl delete -f monitoring/pushgateway-deployment.yaml -n cse239fall2025        # Delete Pushgateway
kubectl delete -f scripts/nginx-hpa.yaml -n cse239fall2025                        # Delete HPA
helm uninstall dsb-socialnetwork -n cse239fall2025                                # Uninstall Social Network app
kubectl get pods -n cse239fall2025                                                # Verify all pods are deleted
```
