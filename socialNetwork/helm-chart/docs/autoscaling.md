# Horizontal Pod Autoscaling (HPA) Guide

## Overview

Horizontal Pod Autoscaler (HPA) automatically scales the number of pods in a deployment based on observed CPU/memory utilization.

## How HPA Works

```
┌─────────────────────────────────────────────────────────────┐
│  Load Increases                                             │
│                    ↓                                         │
│  CPU/Memory Utilization > 70%                               │
│                    ↓                                         │
│  HPA Controller Detects                                      │
│                    ↓                                         │
│  Scales Up: 1 pod → 3 pods                                   │
│                    ↓                                         │
│  Load Distributed Across More Pods                           │
│                    ↓                                         │
│  Utilization Drops < 70%                                     │
│                    ↓                                         │
│  HPA Scales Down: 3 pods → 1 pod (after stabilization)       │
└─────────────────────────────────────────────────────────────┘
```

## HPA Configuration

### Apply HPA

```bash
kubectl apply -f scripts/hpa-config.yaml -n cse239fall2025
```

### Check HPA Status

```bash
# List all HPAs
kubectl get hpa -n cse239fall2025

# Detailed status
kubectl describe hpa compose-post-service-hpa -n cse239fall2025
```

### Example Output

```
NAME                        REFERENCE                      TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
compose-post-service-hpa    Deployment/compose-post        70%/70% (avg)   1         5         3         5m
home-timeline-service-hpa   Deployment/home-timeline       45%/70% (avg)   1         5         1         5m
```

## HPA Configuration Details

### compose-post-service-hpa

```yaml
minReplicas: 1
maxReplicas: 5
targetCPUUtilization: 70%
targetMemoryUtilization: 80%
```

**Scaling Behavior:**
- **Scale Up**: Add 2 pods every 60 seconds (max 5 pods)
- **Scale Down**: Remove 1 pod every 60 seconds (after 2 min stabilization)

### Other Services

All services follow similar pattern:
- **minReplicas**: 1 (always have at least 1 pod)
- **maxReplicas**: 3-5 (depending on service)
- **targetCPUUtilization**: 70%

## Testing HPA

### Step 1: Apply HPA

```bash
kubectl apply -f scripts/hpa-config.yaml -n cse239fall2025
```

### Step 2: Watch HPA

```bash
# Terminal 1: Watch HPA
kubectl get hpa -n cse239fall2025 -w
```

### Step 3: Generate Load

```bash
# Terminal 2: Run load test
cd scripts
k6 run k6-load-test.js
```

### Step 4: Observe Scaling

You should see:
1. CPU utilization increases
2. HPA detects high utilization
3. Pods scale up (1 → 2 → 3)
4. After load stops, pods scale down

## Monitoring HPA

### Watch HPA Events

```bash
kubectl describe hpa compose-post-service-hpa -n cse239fall2025
```

**Example Events:**
```
Events:
  Type    Reason             Age   From                       Message
  ----    ------             ----  ----                       -------
  Normal  SuccessfulRescale  2m    horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal  SuccessfulRescale  5m    horizontal-pod-autoscaler  New size: 1; reason: All metrics below target
```

### Watch Pod Scaling

```bash
# Watch pods being created/destroyed
kubectl get pods -n cse239fall2025 -w | grep compose-post-service
```

### Grafana Dashboard

Monitor in Grafana:
- **Pod Count Over Time**: Should show scaling events
- **CPU Usage**: Should correlate with scaling
- **Deployment Replicas**: Shows current replica count

## HPA Metrics

HPA uses metrics from **metrics-server**:

```bash
# Check if metrics-server is available
kubectl top pods -n cse239fall2025

# If it works, HPA can get CPU/memory metrics
```

## Troubleshooting

### HPA Not Scaling

**Check 1: Metrics Available**
```bash
kubectl top pods -n cse239fall2025
```

**Check 2: HPA Status**
```bash
kubectl describe hpa compose-post-service-hpa -n cse239fall2025
```

Look for:
- `Metrics: (current / target)` - Should show values
- `Events` - Should show scaling decisions

**Check 3: Pod Resources**
```bash
kubectl get deployment compose-post-service -n cse239fall2025 -o yaml | grep -A 5 resources
```

HPA needs pods to have **resource requests** defined.

### HPA Scaling Too Aggressively

**Solution**: Increase `stabilizationWindowSeconds`:

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 60  # Wait 60s before scaling up
  scaleDown:
    stabilizationWindowSeconds: 300  # Wait 5min before scaling down
```

### HPA Not Scaling Down

**Check**: Scale down stabilization window might be too long.

**Solution**: Reduce `stabilizationWindowSeconds` in scaleDown policy.

## Best Practices

1. ✅ **Set resource requests** on all pods (required for HPA)
2. ✅ **Use appropriate thresholds** (70% CPU is a good default)
3. ✅ **Set minReplicas** to ensure availability
4. ✅ **Set maxReplicas** to prevent resource exhaustion
5. ✅ **Monitor scaling events** in Grafana
6. ✅ **Test scaling** with load tests

## Integration with Load Testing

### Full Test Flow

```bash
# Terminal 1: Watch HPA
kubectl get hpa -n cse239fall2025 -w

# Terminal 2: Watch Pods
kubectl get pods -n cse239fall2025 -w

# Terminal 3: Run Load Test
cd scripts
k6 run k6-load-test.js

# Terminal 4: Monitor Grafana
# Open http://localhost:3000
```

**Expected Behavior:**
1. Load test starts → CPU increases
2. HPA detects → Scales up pods
3. Grafana shows pod count increase
4. Load test ends → CPU decreases
5. HPA detects → Scales down pods (after stabilization)

## Summary

✅ **HPA Applied**: Automatically scales pods based on CPU/memory  
✅ **Monitoring**: Watch scaling in Grafana and kubectl  
✅ **Testing**: Use k6 load tests to trigger scaling  
✅ **Configuration**: Customizable thresholds and policies

