# Horizontal Pod Autoscaling (HPA) Guide

## Overview

Horizontal Pod Autoscaler (HPA) automatically scales the number of pods in a deployment based on observed CPU/memory utilization.

## How HPA Works

```
┌─────────────────────────────────────────────────────────────┐
│  Load Increases                                             │
│                    ↓                                         │
│  CPU/Memory Utilization > Target                            │
│                    ↓                                         │
│  HPA Controller Detects                                      │
│                    ↓                                         │
│  Scales Up: 1 pod → 3 pods                                   │
│                    ↓                                         │
│  Load Distributed Across More Pods                           │
│                    ↓                                         │
│  Utilization Drops Below Target                              │
│                    ↓                                         │
│  HPA Scales Down: 3 pods → 1 pod (after stabilization)       │
└─────────────────────────────────────────────────────────────┘
```

## HPA Configuration

### Apply HPA

```bash
kubectl apply -f scripts/nginx-hpa.yaml -n cse239fall2025
```

### Check HPA Status

```bash
kubectl get hpa -n cse239fall2025
kubectl describe hpa nginx-thrift -n cse239fall2025
```

### Example Output

```
NAME           REFERENCE                 TARGETS           MINPODS   MAXPODS   REPLICAS   AGE
nginx-thrift   Deployment/nginx-thrift   25%/30%, 45%/70%  1         3         1          5m
```

## nginx-thrift HPA Configuration

```yaml
minReplicas: 1
maxReplicas: 3
targetCPUUtilization: 30%
targetMemoryUtilization: 70%
```

**Scaling Behavior:**
- **Scale Up**: Add up to 2 pods every 60 seconds
- **Scale Down**: Remove 1 pod every 60 seconds (after 2 min stabilization)

## Testing HPA

### Step 1: Apply HPA

```bash
kubectl apply -f scripts/nginx-hpa.yaml -n cse239fall2025
```

### Step 2: Watch HPA

```bash
kubectl get hpa -n cse239fall2025 -w
```

### Step 3: Generate Load

```bash
kubectl apply -f scripts/k6-hpa-trigger-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-hpa-trigger
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
kubectl describe hpa nginx-thrift -n cse239fall2025
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
kubectl get pods -n cse239fall2025 -w | grep nginx-thrift
```

### Grafana Dashboard

Monitor in Grafana:
- **Pod Count Over Time**: Should show scaling events
- **CPU Usage**: Should correlate with scaling
- **Deployment Replicas**: Shows current replica count

## HPA Metrics

HPA uses metrics from **metrics-server**:

```bash
kubectl top pods -n cse239fall2025
```

## Troubleshooting

### HPA Not Scaling

**Check 1: Metrics Available**
```bash
kubectl top pods -n cse239fall2025
```

**Check 2: HPA Status**
```bash
kubectl describe hpa nginx-thrift -n cse239fall2025
```

Look for:
- `Metrics: (current / target)` - Should show values
- `Events` - Should show scaling decisions

**Check 3: Pod Resources**
```bash
kubectl get deployment nginx-thrift -n cse239fall2025 -o yaml | grep -A 5 resources
```

HPA needs pods to have **resource requests** defined.

### HPA Scaling Too Aggressively

**Solution**: Increase `stabilizationWindowSeconds`:

```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 60
  scaleDown:
    stabilizationWindowSeconds: 300
```

### HPA Not Scaling Down

**Check**: Scale down stabilization window might be too long.

**Solution**: Reduce `stabilizationWindowSeconds` in scaleDown policy.

## Integration with Load Testing

### Full Test Flow

```bash
# Terminal 1: Watch HPA
kubectl get hpa -n cse239fall2025 -w

# Terminal 2: Watch Pods
kubectl get pods -n cse239fall2025 -w | grep nginx-thrift

# Terminal 3: Run HPA Trigger Test
kubectl apply -f scripts/k6-hpa-trigger-job.yaml -n cse239fall2025
kubectl logs -f -n cse239fall2025 -l app=k6-hpa-trigger

# Terminal 4: Monitor Grafana
# Open https://grafana-haardhik.nrp-nautilus.io/d/social-network-nautilus/social-network-nautilus-dashboard
```

**Expected Behavior:**
1. Load test starts → CPU increases
2. HPA detects → Scales up pods
3. Grafana shows pod count increase
4. Load test ends → CPU decreases
5. HPA detects → Scales down pods (after stabilization)

## Cleanup

```bash
kubectl delete -f scripts/nginx-hpa.yaml -n cse239fall2025
```
