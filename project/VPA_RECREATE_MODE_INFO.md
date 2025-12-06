# VPA Recreate Mode - Automatic Scaling

## ✅ Status: VPA is now in Recreate Mode

Your VPA has been switched to **Recreate mode**, which means:

### What This Means:
- ✅ **Automatic Updates**: VPA will automatically apply recommendations to pods
- ✅ **Resource Limits Enforced**: VPA will stay within `minAllowed` and `maxAllowed` limits
- ✅ **Independent Operation**: VPA will scale resources automatically during experiments
- ⚠️ **Pod Recreation**: When recommendations change, pods will be recreated (not updated in-place)

### Current Configuration:

**VPA Mode**: `Recreate`  
**Target**: `user-service-deployment`

**Resource Limits** (from `user-service-vpa.yaml`):
- **Min Allowed**:
  - CPU: 100m (0.1 CPU)
  - Memory: 128Mi
- **Max Allowed**:
  - CPU: 2000m (2 CPUs)
  - Memory: 2Gi

**Current Recommendations**:
- CPU: 100m
- Memory: ~530MB (555745280 bytes)

### How It Works:

1. **VPA Monitors**: VPA continuously monitors resource usage
2. **Generates Recommendations**: Based on historical usage, VPA recommends optimal resources
3. **Applies Automatically**: In Recreate mode, VPA automatically updates the deployment
4. **Recreates Pods**: Kubernetes recreates pods with new resource settings
5. **Stays Within Limits**: All recommendations are constrained by `minAllowed` and `maxAllowed`

### Resource Limits Protection:

✅ **You're protected** - The VPA configuration includes:
- `minAllowed`: Prevents VPA from recommending too little (would cause OOM/CPU throttling)
- `maxAllowed`: Prevents VPA from recommending too much (would waste resources)

These limits are defined in:
- `kubernetes/autoscaling/user-service-vpa.yaml` (base configuration)
- `kubernetes/autoscaling/user-service-vpa-experiments.yaml` (experiment configurations)

### Experiment Configurations Updated:

All experiment configurations now use **Recreate mode**:
- ✅ `user-service-vpa-conservative` → Recreate
- ✅ `user-service-vpa-moderate` → Recreate
- ✅ `user-service-vpa-aggressive` → Recreate
- ✅ `user-service-vpa-cpu-optimized` → Recreate
- ✅ `user-service-vpa-memory-optimized` → Recreate

### Running Experiments:

Now you can simply:

```bash
# Apply an experiment configuration
./scripts/apply-vpa-experiment.sh apply conservative

# Run a test - VPA will automatically adjust resources during the test
./scripts/run-k6-tests.sh constant-load

# Check what VPA did
kubectl describe vpa user-service-vpa-conservative -n default
kubectl get deployment user-service-deployment -n default -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'
```

### What to Expect:

1. **During Tests**: VPA will monitor resource usage
2. **After Tests**: VPA will generate recommendations based on usage
3. **Automatic Updates**: VPA will automatically update pod resources (within limits)
4. **Pod Recreation**: Pods will be recreated with new resources (brief interruption)

### Monitoring VPA Activity:

```bash
# Watch VPA recommendations change
watch -n 5 'kubectl get vpa -n default'

# Check deployment resources (what VPA applied)
kubectl get deployment user-service-deployment -n default -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.'

# Check actual pod resources
kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].spec.containers[0].resources}' | jq '.'

# View VPA events
kubectl describe vpa user-service-vpa -n default | grep -A 10 "Events:"
```

### Important Notes:

1. **Pod Recreation**: In Recreate mode, pods are recreated (not updated in-place). This means:
   - Brief service interruption when resources change
   - Pods restart with new resource settings
   - This is normal and expected behavior

2. **Resource Limits**: VPA will never recommend:
   - Less than `minAllowed` (prevents under-provisioning)
   - More than `maxAllowed` (prevents over-provisioning)

3. **Recommendation Confidence**: VPA needs time to collect data:
   - Run tests to generate load
   - VPA needs ~24 hours of data for high-confidence recommendations
   - Initial recommendations may be conservative

4. **Experiment Isolation**: Each experiment configuration has its own limits:
   - Conservative: CPU 100-500m, Memory 128-512Mi
   - Moderate: CPU 200-1000m, Memory 256Mi-1Gi
   - Aggressive: CPU 500-2000m, Memory 512Mi-2Gi
   - etc.

### Troubleshooting:

**VPA not updating resources?**
- Check if VPA has recommendations: `kubectl describe vpa user-service-vpa -n default`
- VPA needs usage data - run a test first
- Check VPA mode: Should be "Recreate"

**Pods being recreated too often?**
- This is normal in Recreate mode when recommendations change
- Consider using "Off" mode if you want manual control

**Resources outside limits?**
- Check VPA configuration: `kubectl get vpa user-service-vpa -n default -o yaml`
- Verify `minAllowed` and `maxAllowed` are set correctly

### Next Steps:

1. ✅ VPA is in Recreate mode
2. ✅ All experiment configs updated to Recreate mode
3. ✅ Resource limits are defined and enforced
4. 🚀 **Ready to run experiments!**

```bash
# Start with a conservative experiment
./scripts/apply-vpa-experiment.sh apply conservative
./scripts/run-k6-tests.sh constant-load
```

