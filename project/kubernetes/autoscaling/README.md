# Autoscaling Configuration Guide

## Overview

This directory contains Horizontal Pod Autoscaler (HPA) and Vertical Pod Autoscaler (VPA) configurations for performance/cost trade-off analysis. The goal is to find the optimal configuration that maintains **<500ms average end-to-end response time** while minimizing GCP cost.

## Files

### HPA Configurations

1. **`user-service-hpa-latency.yaml`** - Latency-based autoscaling
   - Scales based on response time metrics
   - Primary metric: `http_request_duration_seconds` (target: <400ms)
   - Secondary metric: CPU utilization (safety check)
   - **Requires Prometheus Adapter** (see setup below)

2. **`user-service-hpa-resource.yaml`** - Resource-based autoscaling (baseline)
   - Scales based on CPU and memory utilization
   - Traditional approach for comparison
   - Works out of the box (no Prometheus Adapter needed)

### VPA Configurations

**`user-service-vpa-experiments.yaml`** - Multiple VPA configurations:
- **Conservative**: Lower cost per pod, more pods needed
- **Moderate**: Balanced cost and performance
- **Aggressive**: Higher cost per pod, fewer pods needed
- **CPU-Optimized**: High CPU, moderate memory
- **Memory-Optimized**: Moderate CPU, high memory

## Setup Instructions

### Step 1: Install Prometheus Adapter (for latency-based HPA)

```bash
cd project/
./scripts/setup-prometheus-adapter.sh
```

This installs Prometheus Adapter which exposes Prometheus metrics to Kubernetes HPA.

**Verify installation:**
```bash
# Check if Custom Metrics API is available
kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1'

# Check if latency metrics are exposed
kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_request_duration_seconds'
```

### Step 2: Deploy HPA Configuration

**For latency-based scaling:**
```bash
kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml
```

**For resource-based scaling (baseline):**
```bash
kubectl apply -f kubernetes/autoscaling/user-service-hpa-resource.yaml
```

**Note:** Only apply ONE HPA per deployment at a time.

### Step 3: Deploy VPA Configuration

Choose one VPA configuration from `user-service-vpa-experiments.yaml`:

```bash
# Apply conservative VPA
kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml
# Then delete others: kubectl delete vpa user-service-vpa-moderate user-service-vpa-aggressive ...
```

Or apply individually by editing the file and keeping only one VPA definition.

### Step 4: Monitor Autoscaling

```bash
# Watch HPA status
kubectl get hpa -w

# Watch pod count
kubectl get pods -l app=user-service -w

# Check HPA details
kubectl describe hpa user-service-hpa-latency

# Check VPA recommendations
kubectl describe vpa user-service-vpa-moderate
```

## Running Experiments

### Automated Experiment Runner

Use the experiment script to run controlled tests:

```bash
cd project/
./scripts/run-autoscaling-experiments.sh all
```

This will:
1. Apply different HPA/VPA configurations
2. Run latency tests
3. Collect metrics (pod count, resource usage, latency)
4. Save results for analysis

### Manual Experiment Process

1. **Apply configuration:**
   ```bash
   kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml
   ```

2. **Wait for stabilization** (2-5 minutes)

3. **Run load test:**
   ```bash
   ./scripts/run-k6-tests.sh constant-load
   ```

4. **Collect metrics:**
   ```bash
   # Pod count
   kubectl get deployment user-service-deployment -o jsonpath='{.status.replicas}'
   
   # Resource usage
   kubectl top pods -l app=user-service
   
   # HPA status
   kubectl get hpa user-service-hpa-latency -o yaml
   
   # VPA recommendations
   kubectl get vpa user-service-vpa-moderate -o yaml
   ```

5. **Calculate cost:**
   - Pod count × Resource per pod × Time × GCP pricing
   - Use GCP Pricing Calculator: https://cloud.google.com/products/calculator

6. **Record results:**
   - Latency (p50, p95, p99)
   - Pod count
   - CPU/memory usage
   - Estimated cost per request

## Experiment Matrix

| Experiment | HPA Type | VPA Config | Expected Outcome |
|------------|----------|------------|-------------------|
| 1 | Latency-based | None | Fast response to latency spikes |
| 2 | Resource-based | None | Baseline for comparison |
| 3 | Latency-based | Conservative | Lower cost, more pods |
| 4 | Latency-based | Moderate | Balanced |
| 5 | Latency-based | Aggressive | Higher cost, fewer pods |
| 6 | Latency-based | CPU-optimized | Better for CPU-bound workloads |
| 7 | Latency-based | Memory-optimized | Better for memory-bound workloads |

## Metrics to Track

For each experiment, record:

1. **Latency Metrics:**
   - Average response time (should be <500ms)
   - p95 response time
   - p99 response time

2. **Cost Metrics:**
   - Average pod count
   - CPU usage per pod
   - Memory usage per pod
   - Estimated cost per request

3. **Performance Metrics:**
   - Requests per second (throughput)
   - Error rate
   - Scaling events (scale up/down frequency)

## Analysis

After running experiments:

1. **Plot latency vs cost** for each configuration
2. **Identify the configuration** that meets <500ms target with lowest cost
3. **Consider trade-offs:**
   - Latency-based HPA responds faster to traffic spikes
   - Resource-based HPA is more predictable
   - Higher VPA limits = fewer pods but higher cost per pod
   - Lower VPA limits = more pods but lower cost per pod

## Troubleshooting

### HPA Not Scaling

**Check metrics availability:**
```bash
# For resource-based HPA
kubectl top nodes
kubectl top pods

# For latency-based HPA
kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1'
```

**Check HPA status:**
```bash
kubectl describe hpa user-service-hpa-latency
# Look for "unable to get metrics" errors
```

**Common issues:**
- Metrics server not installed (for resource-based HPA)
- Prometheus Adapter not installed (for latency-based HPA)
- Metrics not exposed by services
- Prometheus not scraping metrics

### VPA Not Working

**Check VPA status:**
```bash
kubectl describe vpa user-service-vpa-moderate
```

**Common issues:**
- VPA not installed in cluster
- VPA admission controller not enabled
- updateMode set to "Off" (only shows recommendations)

### Latency Metrics Not Available

1. **Verify Prometheus is scraping:**
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Visit http://localhost:9090/targets
   ```

2. **Check if services expose metrics:**
   ```bash
   kubectl port-forward svc/user-service 9090:9090
   curl http://localhost:9090/metrics
   ```

3. **Verify Prometheus Adapter configuration:**
   ```bash
   kubectl get configmap adapter-config -n monitoring -o yaml
   ```

## Best Practices

1. **Start with VPA in "Off" mode** to see recommendations first
2. **Test one configuration at a time** for clear results
3. **Run tests for at least 10-15 minutes** to see scaling behavior
4. **Monitor both latency and cost** - don't optimize for one alone
5. **Use production-like load** for realistic results
6. **Document all configurations** and results for comparison

## Next Steps

1. Set up Prometheus Adapter
2. Deploy initial HPA configuration
3. Run baseline experiment (resource-based HPA)
4. Run latency-based HPA experiment
5. Compare results and iterate
6. Find optimal configuration that meets <500ms target with minimal cost

