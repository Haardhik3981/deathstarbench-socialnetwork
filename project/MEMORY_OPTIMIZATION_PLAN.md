# Memory Optimization Plan

## Current Status
- ✅ Fixed duplicate pods (11 services, 6 MongoDB)
- ⚠️ Need to check for memory limit violations
- ⚠️ Need to optimize memory requests/limits

## Steps to Check Memory Issues

### 1. Check Current Pod Status
```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/check-pod-status.sh
```

### 2. Check Memory Usage
```bash
./scripts/check-memory-usage.sh
```

### 3. Look for OOMKilled Pods
```bash
kubectl get pods | grep -i oom
kubectl get pods | grep -i evicted
```

### 4. Check Node Memory Capacity
```bash
kubectl describe nodes | grep -A 10 "Allocatable"
kubectl describe nodes | grep -A 10 "Allocated resources"
```

## Common Memory Issues

### OOMKilled Pods
If pods are being killed due to OOM (Out Of Memory):
1. Check pod logs: `kubectl logs <pod-name> --previous`
2. Increase memory limit in deployment YAML
3. Redeploy the pod

### High Memory Requests
If memory requests are too high:
1. Check actual memory usage: `kubectl top pods`
2. Reduce memory requests in deployment YAML
3. Allow pods to use more memory if needed

### Node Memory Exhaustion
If nodes are out of memory:
1. Check total requests vs capacity
2. Optimize memory requests/limits
3. Scale cluster if necessary

## Next Steps
1. Run diagnostics
2. Identify problematic pods
3. Adjust memory limits/requests
4. Monitor and verify

