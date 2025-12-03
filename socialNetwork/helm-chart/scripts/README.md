# Social Network Load Testing Scripts

This directory contains load testing scripts and autoscaler configurations for the Social Network application.

## Prerequisites

1. **Install k6** (load testing tool):
   ```bash
   # macOS
   brew install k6
   
   # Linux
   sudo gpg -k
   sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
   echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
   sudo apt-get update
   sudo apt-get install k6
   ```

2. **Port-forward the application**:
   ```bash
   kubectl port-forward deployment/nginx-thrift 8080:8080 -n cse239fall2025
   ```

3. **Start the metrics pusher** (for Grafana monitoring):
   ```bash
   kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025
   ../push-metrics.sh
   ```

## Quick Start

Use the interactive runner script:

```bash
chmod +x run-tests.sh
./run-tests.sh
```

Or run specific commands:

```bash
./run-tests.sh prereq      # Check prerequisites
./run-tests.sh hpa         # Apply HPA
./run-tests.sh vpa         # Apply VPA
./run-tests.sh load        # Run load test
./run-tests.sh stress      # Run stress test
./run-tests.sh soak        # Run soak test
./run-tests.sh watch-hpa   # Watch HPA scaling
./run-tests.sh watch-pods  # Watch pod status
```

## Test Types

### 1. Load Test (`k6-load-test.js`)
- **Purpose**: Test normal expected load conditions
- **Duration**: ~14 minutes
- **Load Pattern**: 
  - Ramp to 50 users (2 min)
  - Sustain 50 users (5 min)
  - Ramp to 100 users (2 min)
  - Sustain 100 users (3 min)
  - Ramp down (2 min)

```bash
k6 run k6-load-test.js
```

### 2. Stress Test (`k6-stress-test.js`)
- **Purpose**: Find the breaking point of the system
- **Duration**: ~15 minutes
- **Load Pattern**: Aggressive ramp from 50 → 600 users

```bash
k6 run k6-stress-test.js
```

### 3. Soak Test (`k6-soak-test.js`)
- **Purpose**: Test system stability over extended period
- **Duration**: ~30 minutes
- **Load Pattern**: Sustained 75 users

```bash
k6 run k6-soak-test.js
```

## Autoscaler Configuration

### Horizontal Pod Autoscaler (HPA)

```bash
kubectl apply -f hpa-config.yaml -n cse239fall2025
```

Configured for:
- compose-post-service (1-5 replicas)
- home-timeline-service (1-5 replicas)
- user-timeline-service (1-5 replicas)
- nginx-thrift (1-3 replicas)
- post-storage-service (1-5 replicas)

**Trigger**: CPU utilization > 70%

### Vertical Pod Autoscaler (VPA)

```bash
kubectl apply -f vpa-config.yaml -n cse239fall2025
```

**Note**: VPA requires the VPA controller to be installed in the cluster.

Check if available:
```bash
kubectl get crd | grep verticalpodautoscalers
```

## Monitoring During Tests

1. **Grafana Dashboard** (http://localhost:3000):
   - Watch CPU/Memory usage in real-time
   - See pod count changes when HPA triggers

2. **Watch HPA scaling**:
   ```bash
   kubectl get hpa -n cse239fall2025 -w
   ```

3. **Watch pod status**:
   ```bash
   kubectl get pods -n cse239fall2025 -w
   ```

4. **View HPA events**:
   ```bash
   kubectl describe hpa -n cse239fall2025
   ```

## Expected Results

### Load Test
- p95 latency < 500ms
- Error rate < 10%
- Throughput: 50-100 req/s

### Stress Test
- Find breaking point (where errors > 10%)
- Observe latency degradation
- Watch HPA scale up pods

### Soak Test
- Error rate should stay < 5%
- Latency should remain stable
- Memory should not continuously grow

## Output Files

After each test, results are saved to:
- `load-test-results.json`
- `stress-test-results.json`
- `soak-test-results.json`

## Troubleshooting

### k6: command not found
```bash
brew install k6
```

### Connection refused
Make sure port-forward is running:
```bash
kubectl port-forward deployment/nginx-thrift 8080:8080 -n cse239fall2025
```

### HPA not scaling
1. Check if metrics-server is available:
   ```bash
   kubectl top pods -n cse239fall2025
   ```
2. Check HPA status:
   ```bash
   kubectl describe hpa <name> -n cse239fall2025
   ```

### VPA not working
VPA controller may not be installed on Nautilus. Use HPA instead.

