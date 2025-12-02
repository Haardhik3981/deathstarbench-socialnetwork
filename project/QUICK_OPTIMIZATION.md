# Quick Optimization - Try Before Scaling

## You're Right to Question This!

**Expected CPU:** ~2250m  
**Actual Requested:** 5685m  
**Waste:** ~3400m (150% more than needed!)

## Quick Check - Find the Waste

Run this audit:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/find-cpu-waste.sh
```

This will show:
1. How many pods of each type are running
2. If there are duplicate pods
3. Where the extra CPU is coming from

## Quick Fix - Reduce nginx-thrift CPU First

Before scaling, try reducing nginx-thrift CPU request (it doesn't need 100m for dev/testing):

```bash
kubectl patch deployment nginx-thrift-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx-thrift","resources":{"requests":{"cpu":"50m"}}}]}}}}'
```

This alone might free up enough CPU (50m) to allow it to schedule on current nodes.

## Then Check What's Actually Running

```bash
# See all pods
kubectl get pods | wc -l

# Count by type
kubectl get pods | grep service | wc -l  # Should be ~11
kubectl get pods | grep mongodb | wc -l  # Should be ~6
```

## Possible Issues

1. **Old pods still running** - Even after cleanup, some might remain
2. **Pods from multiple deployments** - Check if you have old deployment versions still running
3. **High database requests** - Databases might be requesting too much

## Recommended Order

1. **Try reducing nginx-thrift CPU** (quick test - might work immediately)
2. **Run audit script** (find where waste is)
3. **Clean up duplicates** (if found)
4. **Then scale** (only if optimization doesn't work)

Let's optimize first, then scale if needed!

