# Detailed HPA Configuration Explanation

This document explains every aspect of the Horizontal Pod Autoscaler (HPA) configuration, based on the `kubectl describe hpa` output.

## Understanding the `kubectl describe hpa` Output

### Basic Information

```
Name: user-service-hpa
Namespace: default
Reference: Deployment/user-service-deployment
```

**What it means:**
- The HPA is named `user-service-hpa` and controls the `user-service-deployment`
- All scaling decisions affect pods in this deployment

**How to adjust:**
- Edit `kubernetes/autoscaling/user-service-hpa.yaml` and change the `name` or `scaleTargetRef.name`
- Apply: `kubectl apply -f kubernetes/autoscaling/user-service-hpa.yaml`

---

## Metrics Section

```
Metrics: ( current / target )
  resource cpu on pods (as a percentage of request):     0% (0) / 70%
  resource memory on pods (as a percentage of request): 31% (41259008) / 80%
```

### CPU Metric: `0% (0) / 70%`

**What it means:**
- **Current**: 0% CPU utilization (0 millicores used)
- **Target**: 70% CPU utilization
- **Calculation**: HPA calculates desired replicas as: `current_replicas × (current_utilization / target_utilization)`
  - Example: If CPU is 140%, desired replicas = 2 × (140/70) = 4 pods

**Why 70%?**
- **Too low (e.g., 50%)**: System scales up too aggressively → higher cost, more pods than needed
- **Too high (e.g., 90%)**: System waits too long to scale → risk of latency spikes, potential overload
- **70% is a good balance**: Leaves headroom for traffic spikes while not over-provisioning

**How to adjust:**
```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70  # Change this value (50-90 recommended)
```

**Is current setting ideal?**
- ✅ **Yes, for baseline testing**: 70% is a standard industry practice
- ⚠️ **Consider lowering to 60%** if you see latency spikes during load tests
- ⚠️ **Consider raising to 80%** if cost is more important than responsiveness

### Memory Metric: `31% (41259008) / 80%`

**What it means:**
- **Current**: 31% memory utilization (~41MB used out of ~133MB requested)
- **Target**: 80% memory utilization
- **Calculation**: Same formula as CPU, but for memory

**Why 80%?**
- Memory is typically less volatile than CPU
- Higher threshold (80% vs 70%) because memory doesn't spike as quickly
- Prevents unnecessary scaling from temporary memory increases

**How to adjust:**
```yaml
metrics:
- type: Resource
  resource:
    name: memory
    target:
      type: Utilization
      averageUtilization: 80  # Change this value (70-90 recommended)
```

**Is current setting ideal?**
- ✅ **Yes**: 80% is appropriate for memory
- ⚠️ **Consider lowering to 75%** if you see OOM (Out of Memory) kills
- ⚠️ **Consider raising to 85%** if memory is not a bottleneck

**Important Note:**
- HPA uses the **maximum** of all metrics to decide scaling
- If CPU says "scale to 4 pods" and memory says "scale to 3 pods", HPA scales to 4 pods
- This ensures both CPU and memory constraints are met

---

## Replica Limits

```
Min replicas: 2
Max replicas: 10
Deployment pods: 2 current / 2 desired
```

### Min Replicas: 2

**What it means:**
- Always keep at least 2 pods running, even if metrics are below target
- Provides high availability (if one pod fails, the other continues serving)

**Why 2?**
- **Too low (1)**: Single point of failure, no redundancy
- **Too high (e.g., 5)**: Wastes resources when idle, increases baseline cost
- **2 is good**: Provides redundancy without excessive cost

**How to adjust:**
```yaml
minReplicas: 2  # Change this value
```

**Is current setting ideal?**
- ✅ **Yes, for testing**: 2 provides good availability
- ⚠️ **Consider 1** if cost is critical and you can tolerate brief downtime
- ⚠️ **Consider 3** if you need higher availability for production

### Max Replicas: 10

**What it means:**
- Never create more than 10 pods, even if metrics exceed target
- Acts as a cost control mechanism

**Why 10?**
- **Too low (e.g., 5)**: May not handle peak load, could cause latency spikes
- **Too high (e.g., 50)**: Risk of runaway scaling, high costs
- **10 is reasonable**: Should handle moderate traffic spikes

**How to adjust:**
```yaml
maxReplicas: 10  # Change this value
```

**Is current setting ideal?**
- ⚠️ **Depends on your load tests**: If k6 tests show you need more than 10 pods, increase this
- ⚠️ **Monitor during tests**: If HPA hits max replicas and latency still increases, you need more
- ✅ **Good starting point**: 10 is reasonable for initial experiments

**How to determine ideal max:**
1. Run your peak/stress test
2. Watch `kubectl get hpa -w`
3. If it hits max replicas and latency is still high, increase maxReplicas
4. If it never reaches 10, you can lower it to save cost

---

## Scaling Behavior: Scale Up

```
Scale Up:
  Stabilization Window: 60 seconds
  Select Policy: Max
  Policies:
    - Type: Percent  Value: 100  Period: 15 seconds
    - Type: Pods     Value: 2    Period: 15 seconds
```

### Stabilization Window: 60 seconds

**What it means:**
- Wait 60 seconds after the last scale-up before considering another scale-up
- Prevents rapid oscillation (scaling up and down repeatedly)

**Why 60 seconds?**
- **Too short (e.g., 15s)**: May cause thrashing if metrics fluctuate
- **Too long (e.g., 300s)**: Slow to respond to sudden traffic spikes
- **60s is good**: Balances responsiveness with stability

**How to adjust:**
```yaml
scaleUp:
  stabilizationWindowSeconds: 60  # Change this value
```

**Is current setting ideal?**
- ✅ **Yes, for most cases**: 60s is a good default
- ⚠️ **Consider 30s** if you need faster response to traffic spikes
- ⚠️ **Consider 90s** if you see too much scaling activity

### Select Policy: Max

**What it means:**
- When multiple policies suggest different replica counts, use the **maximum** (most aggressive scaling)
- Ensures the system scales up quickly when needed

**Why Max?**
- **Max**: Aggressive scaling up (good for handling traffic spikes)
- **Min**: Conservative scaling up (saves cost but may lag behind traffic)
- **Max is better for scale-up**: Better to over-provision slightly than under-provision

**How to adjust:**
```yaml
scaleUp:
  selectPolicy: Max  # Options: Max, Min
```

**Is current setting ideal?**
- ✅ **Yes**: Max is the right choice for scale-up

### Policies

#### Policy 1: Percent = 100%, Period = 15s

**What it means:**
- Every 15 seconds, HPA can increase replicas by up to 100% of current count
- Example: If you have 2 pods, can add 2 more (100% of 2) every 15s
- Maximum rate: 2 → 4 → 8 → 10 (hits max) in 45 seconds

**Why 100%?**
- **Too low (e.g., 50%)**: Slow scaling, may not keep up with traffic spikes
- **Too high (e.g., 200%)**: Very aggressive, may over-provision
- **100% is good**: Doubles capacity quickly when needed

**How to adjust:**
```yaml
policies:
- type: Percent
  value: 100  # Change this (50-200 recommended)
  periodSeconds: 15  # Change this (10-30 recommended)
```

**Is current setting ideal?**
- ✅ **Yes**: 100% every 15s is a good balance
- ⚠️ **Consider 50%** if you want more gradual scaling (saves cost)
- ⚠️ **Consider 200%** if you need very fast scaling (higher cost)

#### Policy 2: Pods = 2, Period = 15s

**What it means:**
- Every 15 seconds, HPA can add up to 2 pods
- Example: 2 → 4 → 6 → 8 → 10 in 60 seconds

**Why 2 pods?**
- Provides a fixed increment regardless of current replica count
- Useful when you have few replicas (Percent policy might be too slow)

**How to adjust:**
```yaml
policies:
- type: Pods
  value: 2  # Change this (1-5 recommended)
  periodSeconds: 15  # Change this
```

**Is current setting ideal?**
- ✅ **Yes**: Adding 2 pods at a time is reasonable
- ⚠️ **Consider 1** if you want more gradual scaling
- ⚠️ **Consider 3-4** if you need faster scaling (but watch costs)

**How the two policies work together:**
- HPA evaluates both policies every 15 seconds
- Policy 1 (Percent): 2 pods × 100% = can add 2 pods → suggests 4 pods
- Policy 2 (Pods): can add 2 pods → suggests 4 pods
- Select Policy: Max → chooses 4 pods (same in this case, but if different, picks higher)

---

## Scaling Behavior: Scale Down

```
Scale Down:
  Stabilization Window: 300 seconds
  Select Policy: Min
  Policies:
    - Type: Percent  Value: 50  Period: 60 seconds
```

### Stabilization Window: 300 seconds (5 minutes)

**What it means:**
- Wait 5 minutes after the last scale-down before considering another scale-down
- Much longer than scale-up window (60s vs 300s)

**Why 300 seconds?**
- **Scale-down should be slower than scale-up**: Prevents thrashing
- **Too short (e.g., 60s)**: May scale down too quickly, then scale back up (wasteful)
- **Too long (e.g., 600s)**: Keeps unnecessary pods running (wasteful)
- **300s (5 min) is good**: Ensures traffic has truly decreased before scaling down

**How to adjust:**
```yaml
scaleDown:
  stabilizationWindowSeconds: 300  # Change this value
```

**Is current setting ideal?**
- ✅ **Yes**: 5 minutes is a good default for scale-down
- ⚠️ **Consider 180s (3 min)** if you want to save costs faster
- ⚠️ **Consider 600s (10 min)** if you see too much scale-down/scale-up oscillation

### Select Policy: Min

**What it means:**
- When multiple policies suggest different replica counts, use the **minimum** (most conservative scaling)
- Ensures the system scales down slowly and conservatively

**Why Min?**
- **Min**: Conservative scale-down (saves cost but may keep extra pods)
- **Max**: Aggressive scale-down (saves more cost but risk of scaling down too much)
- **Min is better for scale-down**: Better to keep a few extra pods than scale down too aggressively

**How to adjust:**
```yaml
scaleDown:
  selectPolicy: Min  # Options: Max, Min
```

**Is current setting ideal?**
- ✅ **Yes**: Min is the right choice for scale-down

### Policy: Percent = 50%, Period = 60s

**What it means:**
- Every 60 seconds, HPA can decrease replicas by up to 50% of current count
- Example: 10 → 5 → 2 (min) in 2 minutes

**Why 50%?**
- **Too low (e.g., 25%)**: Very slow scale-down, wastes resources
- **Too high (e.g., 75%)**: Too aggressive, may scale down too much
- **50% is good**: Halves capacity gradually

**Why 60 seconds (vs 15s for scale-up)?**
- Scale-down should be slower than scale-up
- Gives time to confirm traffic has truly decreased

**How to adjust:**
```yaml
policies:
- type: Percent
  value: 50  # Change this (25-75 recommended)
  periodSeconds: 60  # Change this (30-120 recommended)
```

**Is current setting ideal?**
- ✅ **Yes**: 50% every 60s is a good default
- ⚠️ **Consider 25%** if you want very gradual scale-down (more conservative)
- ⚠️ **Consider 75%** if you want faster cost reduction (more aggressive)

---

## Conditions Section

```
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    ReadyForNewScale  recommended size matches current size
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
```

### AbleToScale: True

**What it means:**
- HPA can make scaling decisions
- Deployment is ready to scale (pods are ready, not in pending state)

**If False:**
- Deployment might be updating (rolling update in progress)
- Pods might be in CrashLoopBackOff
- **Action**: Check deployment status: `kubectl get deployment user-service-deployment`

**Is current status ideal?**
- ✅ **Yes**: True means everything is working

### ScalingActive: True

**What it means:**
- HPA is successfully reading metrics and calculating desired replicas
- Metrics are available and valid

**If False:**
- Metrics server might not be installed
- Metrics might not be available yet (pods too new)
- **Action**: Check metrics server: `kubectl top pods`

**Is current status ideal?**
- ✅ **Yes**: True means metrics are working

### ScalingLimited: True, Reason: TooFewReplicas

**What it means:**
- HPA calculated that it wants fewer replicas than `minReplicas`
- Currently: HPA wants 2 pods, minReplicas is 2, so it's at the minimum

**Why this happens:**
- Current metrics (0% CPU, 31% memory) are below targets (70% CPU, 80% memory)
- HPA would scale down, but `minReplicas: 2` prevents it

**Is this ideal?**
- ✅ **Yes, this is expected**: When idle, HPA stays at minimum replicas
- This is the correct behavior - you want at least 2 pods for availability

**If you see "TooManyReplicas":**
- HPA wants more pods than `maxReplicas` allows
- **Action**: Increase `maxReplicas` or investigate why metrics are so high

---

## Current State Analysis

Based on your output:
- **CPU**: 0% (very low, system is idle)
- **Memory**: 31% (moderate, within normal range)
- **Replicas**: 2/2 (at minimum, which is correct for idle state)

**What this tells you:**
1. ✅ System is healthy and idle
2. ✅ HPA is working correctly (staying at minimum when idle)
3. ✅ Ready for load testing - when you run k6 tests, you should see:
   - CPU and memory increase
   - HPA scales up if metrics exceed targets
   - Replicas increase from 2 toward 10 (depending on load)

---

## Recommendations for Your Experiments

### For Baseline Testing (Current Config)

**Current settings are good for:**
- ✅ Baseline comparison experiments
- ✅ Understanding how resource-based autoscaling works
- ✅ Comparing with latency-based autoscaling

**No changes needed** - this is a solid baseline configuration.

### For Optimizing Performance (<500ms latency target)

**Consider these adjustments:**

1. **Lower CPU target to 60%** (more aggressive scaling):
   ```yaml
   averageUtilization: 60  # Instead of 70
   ```
   - Scales up earlier, more headroom for traffic spikes
   - Higher cost (more pods), but better latency

2. **Increase maxReplicas to 15-20** (if needed):
   ```yaml
   maxReplicas: 15  # Instead of 10
   ```
   - Only if your load tests show you need more than 10 pods

3. **Faster scale-up (if latency spikes during ramp-up)**:
   ```yaml
   scaleUp:
     stabilizationWindowSeconds: 30  # Instead of 60
     policies:
     - type: Percent
       value: 100
       periodSeconds: 10  # Instead of 15
   ```

### For Optimizing Cost

**Consider these adjustments:**

1. **Raise CPU target to 80%** (less aggressive scaling):
   ```yaml
   averageUtilization: 80  # Instead of 70
   ```
   - Fewer pods, lower cost
   - Risk of higher latency during spikes

2. **Faster scale-down**:
   ```yaml
   scaleDown:
     stabilizationWindowSeconds: 180  # Instead of 300
     policies:
     - type: Percent
       value: 50
       periodSeconds: 30  # Instead of 60
   ```

---

## How to Test Different Configurations

1. **Save current config as baseline:**
   ```bash
   cp kubernetes/autoscaling/user-service-hpa.yaml kubernetes/autoscaling/user-service-hpa-baseline.yaml
   ```

2. **Modify the YAML file** with your desired changes

3. **Apply the new config:**
   ```bash
   kubectl apply -f kubernetes/autoscaling/user-service-hpa.yaml
   ```

4. **Wait for HPA to stabilize** (1-2 minutes)

5. **Run your k6 test:**
   ```bash
   ./scripts/run-test-with-metrics.sh constant-load
   ```

6. **Monitor HPA during test:**
   ```bash
   kubectl get hpa -w
   ```

7. **Compare results:**
   - Check metrics CSV for latency
   - Check HPA events: `kubectl describe hpa user-service-hpa`
   - Check pod count: `kubectl get pods -l app=user-service`

8. **Revert if needed:**
   ```bash
   kubectl apply -f kubernetes/autoscaling/user-service-hpa-baseline.yaml
   ```

---

## Summary: Is Current Config Ideal?

**For baseline experiments: ✅ YES**
- All settings are reasonable defaults
- Good starting point for comparison

**For <500ms latency target: ⚠️ MAY NEED ADJUSTMENT**
- Consider lowering CPU target to 60%
- Consider faster scale-up policies
- Monitor during load tests and adjust based on results

**For cost optimization: ⚠️ CAN BE IMPROVED**
- Consider raising CPU target to 80%
- Consider faster scale-down policies
- Balance with latency requirements

**Bottom line:** Your current config is a solid baseline. Use it for initial experiments, then adjust based on your k6 test results to find the optimal performance/cost trade-off.

