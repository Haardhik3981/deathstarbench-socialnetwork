# Experiment Test Plan: k6 Tests + Autoscaling Configurations

## Overview

**Yes, your understanding is correct!** The idea is to run k6 load tests **with different autoscaling configurations** to see how each configuration adapts to the load and measure:
- **Performance**: Latency (p50, p95, p99) - should stay <500ms
- **Cost**: Pod count, resource usage, estimated cost per request
- **Scaling behavior**: How quickly and effectively the system scales

## The Process

### Step-by-Step Workflow

1. **Apply an autoscaling configuration** (HPA + VPA combination)
2. **Wait for stabilization** (2-5 minutes)
3. **Run k6 test** to generate load
4. **Collect metrics** during and after the test
5. **Record results** (latency, pod count, cost)
6. **Change configuration** and repeat
7. **Compare results** to find optimal configuration

## Test Matrix

### Configuration Combinations to Test

| Experiment # | HPA Type | VPA Config | k6 Test | Purpose |
|-------------|----------|------------|---------|---------|
| 1 | Resource-based | None | Constant Load | Baseline - traditional scaling |
| 2 | Latency-based | None | Constant Load | Compare latency vs resource scaling |
| 3 | Latency-based | Conservative | Constant Load | Low cost per pod, more pods |
| 4 | Latency-based | Moderate | Constant Load | Balanced approach |
| 5 | Latency-based | Aggressive | Constant Load | High cost per pod, fewer pods |
| 6 | Latency-based | Moderate | Stress Test | How it handles gradual ramp-up |
| 7 | Latency-based | Moderate | Peak Test | How it handles sudden spikes |
| 8 | Latency-based | Moderate | Endurance Test | Long-term stability (optional) |

## Detailed Test Plan

### Phase 1: Baseline Comparison (Constant Load)

**Goal**: Compare latency-based vs resource-based HPA under steady load

#### Test 1.1: Resource-Based HPA (Baseline)
```bash
# Apply configuration
kubectl apply -f kubernetes/autoscaling/user-service-hpa-resource.yaml
kubectl delete vpa --all  # Ensure no VPA interference

# Wait for stabilization
sleep 120

# Run test
./scripts/run-k6-tests.sh constant-load

# Collect metrics
kubectl get hpa user-service-hpa-resource -o yaml > results/baseline-resource-hpa.yaml
kubectl get pods -l app=user-service -o wide > results/baseline-pods.txt
```

**Metrics to record:**
- Average latency (p50, p95, p99)
- Average pod count
- CPU/memory usage per pod
- Scaling events (scale up/down frequency)
- Estimated cost

#### Test 1.2: Latency-Based HPA
```bash
# Remove previous HPA
kubectl delete hpa user-service-hpa-resource

# Apply latency-based HPA
kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml

# Wait for stabilization
sleep 120

# Run same test
./scripts/run-k6-tests.sh constant-load

# Collect metrics
kubectl get hpa user-service-hpa-latency -o yaml > results/latency-hpa.yaml
```

**Compare with Test 1.1:**
- Which maintains <500ms latency better?
- Which has lower cost?
- Which scales more appropriately?

---

### Phase 2: VPA Impact Analysis (Constant Load)

**Goal**: Understand how different VPA configurations affect performance and cost

#### Test 2.1: Latency HPA + Conservative VPA
```bash
# Apply HPA
kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml

# Apply Conservative VPA (edit file to keep only conservative)
kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml
# Then: kubectl delete vpa user-service-vpa-moderate user-service-vpa-aggressive ...

# Wait for VPA to apply (if using Initial mode)
sleep 300

# Run test
./scripts/run-k6-tests.sh constant-load
```

**Expected outcome:**
- More pods (lower resources per pod)
- Lower cost per pod
- May have higher total cost if many pods needed

#### Test 2.2: Latency HPA + Moderate VPA
```bash
# Switch to Moderate VPA
kubectl delete vpa user-service-vpa-conservative
# Edit file to keep only moderate VPA
kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml

# Wait and test
sleep 300
./scripts/run-k6-tests.sh constant-load
```

**Expected outcome:**
- Balanced pod count
- Moderate cost per pod
- Should be optimal balance

#### Test 2.3: Latency HPA + Aggressive VPA
```bash
# Switch to Aggressive VPA
kubectl delete vpa user-service-vpa-moderate
# Edit file to keep only aggressive VPA
kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml

# Wait and test
sleep 300
./scripts/run-k6-tests.sh constant-load
```

**Expected outcome:**
- Fewer pods (higher resources per pod)
- Higher cost per pod
- May have lower total cost if fewer pods needed

**Compare all three:**
- Which maintains <500ms latency?
- Which has lowest total cost?
- Which has best cost per request?

---

### Phase 3: Load Pattern Analysis (Different k6 Tests)

**Goal**: See how autoscaling behaves under different load patterns

#### Test 3.1: Stress Test (Gradual Ramp-Up)
```bash
# Use best configuration from Phase 2
kubectl apply -f kubernetes/autoscaling/user-service-hpa-latency.yaml
kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml  # Best VPA

# Run stress test (gradual ramp-up)
./scripts/run-k6-tests.sh stress-test
```

**What to observe:**
- How quickly does HPA scale up?
- Does latency stay <500ms during ramp-up?
- Is scaling smooth or does it lag behind load?

#### Test 3.2: Peak Test (Sudden Spike)
```bash
# Same configuration
./scripts/run-k6-tests.sh peak-test
```

**What to observe:**
- How quickly does HPA respond to sudden spike?
- Does latency spike before scaling kicks in?
- Recovery time after spike ends

#### Test 3.3: Endurance Test (Long Duration)
```bash
# Optional - runs for 5+ hours
./scripts/run-k6-tests.sh endurance-test
```

**What to observe:**
- Long-term stability
- Memory leaks
- Consistent performance over time
- Cost over extended period

---

## Metrics Collection Template

For each test, record:

### Performance Metrics (from k6)
```
Test: [Test Name]
Configuration: [HPA Type + VPA Config]
Duration: [Test duration]

Latency:
  - p50 (median): _____ ms
  - p95: _____ ms
  - p99: _____ ms
  - Average: _____ ms
  - Max: _____ ms

Throughput:
  - Requests per second (avg): _____
  - Total requests: _____

Errors:
  - Error rate: _____ %
  - Total errors: _____
```

### Scaling Metrics (from Kubernetes)
```
Pod Count:
  - Initial: _____ pods
  - Peak: _____ pods
  - Average: _____ pods
  - Final: _____ pods

Scaling Events:
  - Scale-ups: _____
  - Scale-downs: _____
  - Time to first scale-up: _____ seconds
  - Time to peak: _____ seconds

Resource Usage (per pod):
  - CPU (avg): _____ m
  - Memory (avg): _____ Mi
  - CPU (peak): _____ m
  - Memory (peak): _____ Mi
```

### Cost Metrics
```
Estimated Cost:
  - Total CPU-hours: _____
  - Total Memory-GB-hours: _____
  - Estimated cost: $ _____
  - Cost per request: $ _____
  - Cost per 1000 requests: $ _____
```

---

## Recommended Test Sequence

### Quick Test (1-2 hours)
1. Resource-based HPA + Constant Load
2. Latency-based HPA + Constant Load
3. Latency HPA + Moderate VPA + Constant Load

**Compare these three** to see which maintains <500ms with lowest cost.

### Comprehensive Test (4-6 hours)
1. All Phase 1 tests (baseline comparison)
2. All Phase 2 tests (VPA analysis)
3. Best configuration + Stress Test
4. Best configuration + Peak Test

### Full Analysis (1-2 days)
1. All tests above
2. Best configuration + Endurance Test
3. Fine-tune best configuration
4. Re-test with variations

---

## Analysis Workflow

### After Each Test

1. **Extract k6 metrics:**
   ```bash
   # From k6 JSON output
   cat k6-results/constant-load_*.json | jq '.metrics.http_req_duration.values'
   ```

2. **Extract Kubernetes metrics:**
   ```bash
   # Pod count over time
   kubectl get hpa user-service-hpa-latency -o jsonpath='{.status.currentReplicas}'
   
   # Resource usage
   kubectl top pods -l app=user-service
   ```

3. **Calculate cost:**
   - Use GCP Pricing Calculator
   - Formula: `(Pod Count × CPU × Memory × Hours) × GCP Pricing`

4. **Record in spreadsheet:**
   - One row per test
   - Columns: Config, Latency (p50/p95/p99), Pod Count, Cost, Notes

### Final Analysis

1. **Create scatter plot:**
   - X-axis: Cost per request
   - Y-axis: Average latency
   - Each point = one test configuration
   - Goal: Find points in bottom-left (low cost, low latency)

2. **Identify optimal configuration:**
   - Maintains <500ms latency ✅
   - Lowest cost per request ✅
   - Scales appropriately ✅

3. **Document findings:**
   - Best configuration
   - Why it's optimal
   - Trade-offs considered

---

## Automation Script

The `run-autoscaling-experiments.sh` script automates this process:

```bash
# Run all experiments
./scripts/run-autoscaling-experiments.sh all

# Run specific experiment
./scripts/run-autoscaling-experiments.sh latency-hpa
```

This will:
1. Apply configuration
2. Wait for stabilization
3. Run k6 test
4. Collect metrics
5. Save results

---

## Key Insights to Look For

### Latency-Based vs Resource-Based HPA
- **Latency-based** should respond faster to traffic spikes
- **Resource-based** may lag (CPU spikes before latency increases)
- **Question**: Which maintains <500ms better under varying load?

### VPA Impact
- **Conservative VPA**: More pods, lower cost per pod
- **Aggressive VPA**: Fewer pods, higher cost per pod
- **Question**: Which has lower total cost while maintaining <500ms?

### Load Pattern Response
- **Constant load**: Baseline performance
- **Stress test**: Scaling efficiency during gradual increase
- **Peak test**: Response time to sudden spikes
- **Question**: Does configuration handle all patterns well?

---

## Success Criteria

A successful configuration:
1. ✅ Maintains <500ms average latency (p50)
2. ✅ Keeps p95 latency reasonable (<1000ms)
3. ✅ Has lowest cost per request
4. ✅ Scales up quickly when needed
5. ✅ Scales down when load decreases (cost optimization)
6. ✅ Doesn't thrash (frequent scale up/down)

---

## Example Results Table

| Config | p50 Latency | p95 Latency | Avg Pods | Cost/1K Req | Meets Target? |
|--------|-------------|-------------|----------|-------------|---------------|
| Resource HPA | 450ms | 800ms | 4 | $0.05 | ✅ |
| Latency HPA | 380ms | 650ms | 5 | $0.06 | ✅ |
| Latency + Conservative VPA | 420ms | 750ms | 6 | $0.055 | ✅ |
| Latency + Moderate VPA | 350ms | 600ms | 4 | $0.045 | ✅ **BEST** |
| Latency + Aggressive VPA | 320ms | 550ms | 3 | $0.055 | ✅ |

In this example, **Latency + Moderate VPA** is optimal: meets latency target with lowest cost.

---

## Next Steps

1. **Start with Phase 1** (baseline comparison)
2. **Run 2-3 configurations** to get a feel for the process
3. **Analyze initial results** to guide further experiments
4. **Focus on Phase 2** (VPA analysis) with best HPA
5. **Validate with Phase 3** (different load patterns)
6. **Document findings** and create final recommendation

This systematic approach will help you find the optimal autoscaling configuration that maintains <500ms latency while minimizing cost!

