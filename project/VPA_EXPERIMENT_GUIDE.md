# VPA Experiment Guide

## Current Status ✅

Your VPA setup is **ready for experiments**:

- ✅ VPA API is installed and available
- ✅ VPA is configured for `user-service-deployment`
- ✅ VPA is providing recommendations (CPU: 100m, Memory: ~530MB)
- ✅ No HPA conflicts (HPA is not active)
- ✅ 5 experiment configurations are ready

## Important: VPA Update Mode

Your VPA is currently in **"Off" mode**, which means:
- ✅ VPA collects usage data and provides recommendations
- ❌ VPA does NOT automatically apply recommendations

### For Experiments, You Have Two Options:

#### Option 1: Manual Application (Recommended for Experiments)
Manually apply VPA recommendations or experiment configurations:

```bash
# Show current recommendations
./scripts/apply-vpa-experiment.sh show-recommendations

# Apply recommendations to deployment
./scripts/apply-vpa-experiment.sh apply-recommendations

# Or apply a specific experiment configuration
./scripts/apply-vpa-experiment.sh list
./scripts/apply-vpa-experiment.sh apply conservative
```

#### Option 2: Automatic Application (Recreate Mode)
Switch VPA to "Recreate" mode to automatically apply recommendations:

```bash
# Switch to Recreate mode (VPA will automatically update pods)
./scripts/apply-vpa-experiment.sh set-mode Recreate

# Note: This will recreate pods when recommendations change
# Good for production, but may interrupt experiments
```

## Experiment Workflow

### Step 1: Choose an Experiment Configuration

Available experiments:
- **conservative**: Lower cost, more pods (CPU: 100-500m, Memory: 128-512Mi)
- **moderate**: Balanced (CPU: 200-1000m, Memory: 256Mi-1Gi)
- **aggressive**: Higher cost, fewer pods, better latency (CPU: 500-2000m, Memory: 512Mi-2Gi)
- **cpu-optimized**: High CPU, moderate memory (CPU: 500-2000m, Memory: 256Mi-1Gi)
- **memory-optimized**: Moderate CPU, high memory (CPU: 200-1000m, Memory: 512Mi-2Gi)

### Step 2: Apply Experiment Configuration

```bash
# List all available experiments
./scripts/apply-vpa-experiment.sh list

# Apply a specific experiment
./scripts/apply-vpa-experiment.sh apply conservative
```

### Step 3: Apply Recommendations to Deployment

If VPA is in "Off" mode, manually apply recommendations:

```bash
# Check current recommendations
./scripts/apply-vpa-experiment.sh show-recommendations

# Apply recommendations (this will update deployment resources)
./scripts/apply-vpa-experiment.sh apply-recommendations
```

### Step 4: Run Test and Collect Metrics

```bash
# Run a k6 test
./scripts/run-k6-tests.sh constant-load

# Or run with metrics collection
./scripts/run-test-with-metrics.sh constant-load
```

### Step 5: Analyze Results

Compare:
- **Latency** (should stay <500ms)
- **Cost** (CPU/memory usage per request)
- **Pod count** (affected by resource allocation)

### Step 6: Try Next Experiment

```bash
# Apply next experiment configuration
./scripts/apply-vpa-experiment.sh apply moderate

# Apply recommendations
./scripts/apply-vpa-experiment.sh apply-recommendations

# Run test again
./scripts/run-k6-tests.sh constant-load
```

## Quick Reference

### Check VPA Status
```bash
# Verify setup
./scripts/verify-vpa-setup.sh

# Show current VPA
kubectl get vpa -n default

# Detailed VPA info
kubectl describe vpa user-service-vpa -n default
```

### Apply Experiment
```bash
# List experiments
./scripts/apply-vpa-experiment.sh list

# Apply experiment
./scripts/apply-vpa-experiment.sh apply <experiment-name>

# Show recommendations
./scripts/apply-vpa-experiment.sh show-recommendations

# Apply recommendations
./scripts/apply-vpa-experiment.sh apply-recommendations
```

### Check Deployment Resources
```bash
# Current deployment resources
kubectl get deployment user-service-deployment -n default -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'

# Current pod resources
kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].spec.containers[0].resources}' | jq '.'
```

## Understanding VPA Recommendations

VPA provides three types of recommendations:

1. **Target**: The recommended resource allocation (what you should use)
2. **Lower Bound**: Minimum safe allocation
3. **Upper Bound**: Maximum safe allocation

For experiments, use the **Target** values.

## Tips for Experiments

1. **Let VPA collect data first**: Run a test to generate load, then check recommendations
2. **Compare configurations**: Run the same test with different VPA configurations
3. **Monitor both metrics**: Track both latency (k6) and resource usage (Prometheus/Grafana)
4. **Clear memory between tests**: Use `./scripts/clear-nonessential-memory.sh` to ensure consistent baseline
5. **Document results**: Record latency, cost, and pod count for each experiment

## Troubleshooting

### No Recommendations Available
```bash
# VPA needs time to collect data. Run a test first:
./scripts/run-k6-tests.sh quick-test

# Then check again:
./scripts/apply-vpa-experiment.sh show-recommendations
```

### Recommendations Not Applied
```bash
# If VPA is in "Off" mode, manually apply:
./scripts/apply-vpa-experiment.sh apply-recommendations

# Or switch to Recreate mode:
./scripts/apply-vpa-experiment.sh set-mode Recreate
```

### Check VPA Status
```bash
# Verify VPA is working
./scripts/verify-vpa-setup.sh

# Check VPA logs (if components are installed)
kubectl logs -n kube-system -l app=vpa-recommender
```

## Next Steps

1. ✅ Verify setup: `./scripts/verify-vpa-setup.sh`
2. ✅ Choose experiment: `./scripts/apply-vpa-experiment.sh list`
3. ✅ Apply experiment: `./scripts/apply-vpa-experiment.sh apply <name>`
4. ✅ Run test: `./scripts/run-k6-tests.sh constant-load`
5. ✅ Analyze results and compare configurations

