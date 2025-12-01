# Autoscaling Guide - Performance/Cost Trade-Off Analysis

## Overview

This guide explains how to configure and run autoscaling experiments to find the optimal configuration that maintains **<500ms average end-to-end response time** while minimizing GCP cost.

## Architecture

### Two Types of Autoscaling

1. **Horizontal Pod Autoscaler (HPA)**
   - Scales the **number of pods** (replicas)
   - More pods = more capacity, but higher cost
   - Can scale based on:
     - CPU/Memory utilization (resource-based)
     - Latency/response time (latency-based) - **requires Prometheus Adapter**

2. **Vertical Pod Autoscaler (VPA)**
   - Scales the **resources per pod** (CPU/memory)
   - More resources per pod = better performance, but higher cost per pod
   - Fewer resources per pod = lower cost per pod, but may need more pods

### The Trade-Off

**Goal:** Maintain <500ms latency while minimizing cost

**Strategies:**
- **Aggressive HPA**: Scale up quickly when latency increases → More pods → Higher cost
- **Aggressive VPA**: Allocate more resources per pod → Fewer pods needed → May be cheaper overall
- **Conservative**: Lower resources → More pods → May be cheaper if pods are small

## Setup Steps

### 1. Install Prometheus Adapter (Required for Latency-Based HPA)

```bash
cd project/
./scripts/setup-prometheus-adapter.sh
```

This enables HPA to scale based on latency metrics from Prometheus.

**Verify:**
```bash
kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1'
```

### 2. Deploy Monitoring (If Not Already Done)

```bash
./scripts/setup-monitoring.sh
```

### 3. Choose Your Experiment Configuration

#### Option A: Latency-Based HPA (Recommended for <500ms target)

```bash
# Apply latency-based HPA
kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml

# Monitor
kubectl get hpa user-service-hpa-latency -w
```

#### Option B: Resource-Based HPA (Baseline for Comparison)

```bash
# Apply resource-based HPA
kubectl apply -f kubernetes/autoscaling/user-service-hpa-resource.yaml

# Monitor
kubectl get hpa user-service-hpa-resource -w
```

#### Option C: Combined HPA + VPA

```bash
# Apply HPA
kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml

# Apply VPA (choose one from experiments file)
# Edit user-service-vpa-experiments.yaml to keep only one VPA definition
kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml
```

## Running Experiments

### Automated Experiment Runner

```bash
cd project/
./scripts/run-autoscaling-experiments.sh all
```

This will:
1. Apply different configurations
2. Run load tests
3. Collect metrics
4. Save results to `autoscaling-results/`

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
   kubectl get hpa -o yaml > results/hpa-status.yaml
   
   # Latency from k6 results
   cat k6-results/constant-load_*.json | jq '.metrics.http_req_duration.values'
   ```

5. **Calculate cost:**
   - Use GCP Pricing Calculator
   - Formula: `(Pod Count × CPU per pod × Memory per pod × Time) × GCP Pricing`

6. **Record results** in a spreadsheet:
   - Configuration name
   - Average latency (p50, p95, p99)
   - Pod count
   - CPU/memory usage
   - Estimated cost per request

## Experiment Configurations

### HPA Configurations

| Configuration | Type | Target Metric | Use Case |
|--------------|------|---------------|----------|
| `user-service-hpa-latency.yaml` | Latency-based | <400ms response time | Maintain <500ms target |
| `user-service-hpa-resource.yaml` | Resource-based | 70% CPU, 80% memory | Baseline comparison |

### VPA Configurations

| Configuration | CPU Range | Memory Range | Cost Profile |
|--------------|-----------|--------------|--------------|
| Conservative | 100m-500m | 128Mi-512Mi | Lower cost per pod |
| Moderate | 200m-1000m | 256Mi-1Gi | Balanced |
| Aggressive | 500m-2000m | 512Mi-2Gi | Higher cost per pod |
| CPU-Optimized | 500m-2000m | 256Mi-1Gi | High CPU, moderate memory |
| Memory-Optimized | 200m-1000m | 512Mi-2Gi | Moderate CPU, high memory |

## Metrics to Track

For each experiment, record:

### Performance Metrics
- **Average latency** (p50) - should be <500ms
- **p95 latency** - 95% of requests
- **p99 latency** - 99% of requests
- **Throughput** (requests per second)
- **Error rate**

### Cost Metrics
- **Average pod count** during test
- **CPU usage per pod** (average)
- **Memory usage per pod** (average)
- **Total CPU-hours** = Pod count × CPU per pod × Hours
- **Total Memory-GB-hours** = Pod count × Memory per pod × Hours
- **Estimated cost** (use GCP pricing)

### Scaling Metrics
- **Scale-up events** (frequency, trigger)
- **Scale-down events** (frequency, trigger)
- **Time to scale** (how quickly HPA responds)

## Analysis

### Creating Comparison Charts

1. **Latency vs Cost Scatter Plot**
   - X-axis: Cost per request
   - Y-axis: Average latency
   - Goal: Find points in bottom-left (low cost, low latency)

2. **Pod Count Over Time**
   - Compare different configurations
   - See which scales more aggressively

3. **Resource Utilization**
   - CPU and memory usage per pod
   - Identify if resources are over/under-provisioned

### Finding Optimal Configuration

The optimal configuration:
- ✅ Maintains <500ms average latency
- ✅ Has lowest cost per request
- ✅ Scales appropriately with load
- ✅ Doesn't thrash (frequent scale up/down)

## Example Experiment Workflow

```bash
# 1. Setup
./scripts/setup-prometheus-adapter.sh
./scripts/setup-monitoring.sh

# 2. Experiment 1: Latency-based HPA only
kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml
./scripts/run-k6-tests.sh constant-load
# Record: latency, pod count, cost

# 3. Experiment 2: Resource-based HPA (baseline)
kubectl delete hpa user-service-hpa-latency
kubectl apply -f kubernetes/autoscaling/user-service-hpa-resource.yaml
./scripts/run-k6-tests.sh constant-load
# Record: latency, pod count, cost

# 4. Experiment 3: Latency HPA + Conservative VPA
kubectl delete hpa user-service-hpa-resource
kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml
# Edit vpa-experiments.yaml to keep only conservative VPA
kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml
./scripts/run-k6-tests.sh constant-load
# Record: latency, pod count, cost

# 5. Compare results and identify optimal configuration
```

## Troubleshooting

### HPA Not Scaling Based on Latency

1. **Check Prometheus Adapter:**
   ```bash
   kubectl get pods -n monitoring | grep prometheus-adapter
   kubectl logs -n monitoring deployment/prometheus-adapter
   ```

2. **Verify metrics are available:**
   ```bash
   kubectl get --raw '/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/http_request_duration_seconds'
   ```

3. **Check Prometheus is scraping:**
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   # Visit http://localhost:9090 and check targets
   ```

### VPA Not Applying Recommendations

1. **Check VPA status:**
   ```bash
   kubectl describe vpa user-service-vpa-moderate
   ```

2. **Check updateMode:**
   - "Off" = only shows recommendations
   - "Initial" = applies when pods are created
   - "Auto" = applies automatically (requires VPA admission controller)

3. **Verify VPA is installed:**
   ```bash
   kubectl get deployment vpa-recommender -n kube-system
   ```

## Best Practices

1. **Start with VPA in "Off" mode** to see recommendations first
2. **Test one configuration at a time** for clear results
3. **Run tests for 10-15 minutes** to see full scaling behavior
4. **Use production-like load** for realistic results
5. **Monitor both latency AND cost** - don't optimize for one alone
6. **Document everything** - configurations, results, observations

## Next Steps

1. ✅ Set up Prometheus Adapter
2. ✅ Deploy baseline HPA (resource-based)
3. ✅ Run baseline experiment
4. ✅ Deploy latency-based HPA
5. ✅ Run latency-based experiment
6. ✅ Compare results
7. ✅ Test VPA configurations
8. ✅ Find optimal configuration
9. ✅ Document findings

## Resources

- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Prometheus Adapter](https://github.com/kubernetes-sigs/prometheus-adapter)
- [GCP Pricing Calculator](https://cloud.google.com/products/calculator)

