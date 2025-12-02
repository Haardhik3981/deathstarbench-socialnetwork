# Optimize Before Scaling - Find Inefficiencies

## Your Question is Valid!

You're requesting **5685m CPU** but should only need **~2250m**. That's **~3400m wasted**!

## Quick Audit

Run these commands to find inefficiencies:

### 1. Check for Duplicate Pods

```bash
# Count pods per deployment type
kubectl get pods | awk '{print $1}' | cut -d'-' -f1-4 | sort | uniq -c | sort -rn

# Look for deployments with multiple pods (should be 1 each for testing)
```

### 2. Check Resource Requests

```bash
# See what each deployment is requesting
kubectl get deployment -o json | jq -r '.items[] | "\(.metadata.name)\t\(.spec.replicas)\t\(.spec.template.spec.containers[0].resources.requests.cpu)"'

# Or simpler - check specific ones
kubectl get deployment user-service-deployment -o jsonpath='{.spec.replicas}{"\t"}{.spec.template.spec.containers[0].resources.requests.cpu}{"\n"}'
```

### 3. Use Audit Script

```bash
./scripts/audit-cpu-usage.sh
```

## Common Inefficiencies

### Issue 1: Multiple Replicas

If deployments have `replicas: 2` or more, reduce to 1 for testing:

```bash
# Check replicas
kubectl get deployment -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas

# Reduce if needed
kubectl scale deployment user-service-deployment --replicas=1
```

### Issue 2: High Database Requests

Databases might be requesting too much CPU. They often don't need 100m each for dev/testing.

### Issue 3: Duplicate Pods

Old pods still consuming resources. Already cleaned up, but verify.

## Quick Optimization (Before Scaling)

### Option A: Reduce nginx-thrift CPU (Fastest)

```bash
# Reduce from 100m to 50m (enough for dev/testing)
kubectl patch deployment nginx-thrift-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx-thrift","resources":{"requests":{"cpu":"50m"}}}]}}}}'
```

This alone might free up 50m and allow it to schedule!

### Option B: Check for Extra Replicas

```bash
# See if any deployments have replicas > 1
kubectl get deployment -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas | grep -v "1$"
```

## Recommended: Try Optimization First

1. **Run audit:**
   ```bash
   ./scripts/audit-cpu-usage.sh
   ```

2. **Reduce nginx-thrift CPU:**
   ```bash
   kubectl patch deployment nginx-thrift-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx-thrift","resources":{"requests":{"cpu":"50m"}}}]}}}}'
   ```

3. **Check if it schedules** (should have ~50m more free now)

4. **If still not enough, then scale to 3 nodes**

This way you'll know if the issue is inefficiency or actually need 3 nodes.

