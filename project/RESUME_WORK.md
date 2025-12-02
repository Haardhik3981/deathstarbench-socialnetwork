# Resuming Work - Memory Optimization

## Current Status
✅ Successfully fixed duplicate pods:
- Services: 11 pods (correct)
- MongoDB: 6 pods (correct)

## Next Steps: Memory Optimization

### Step 1: Check Current Pod Status
Run the comprehensive audit to see what's happening:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/audit-memory.sh
```

This will show:
- Any OOM-killed pods
- CrashLoopBackOff pods (may be memory-related)
- Pending/ContainerCreating pods
- Node memory capacity

### Step 2: Check for Memory Issues
Look for:
- **OOMKilled** pods - killed for exceeding memory limits
- **Evicted** pods - evicted due to node memory pressure
- **CrashLoopBackOff** - may be crashing due to memory issues

### Step 3: Review Memory Limits

Current memory configuration:
- **Services**: 128Mi requests, 512Mi limits
- **MongoDB**: 512Mi requests, 2Gi limits
- **nginx-thrift**: 128Mi requests, 512Mi limits
- **Redis**: Check individual deployments
- **Memcached**: Check individual deployments

### Step 4: Fix Memory Issues

If pods are being killed:
1. Check logs: `kubectl logs <pod-name> --previous`
2. Increase memory limit if needed
3. Or optimize the application to use less memory

If nodes are out of memory:
1. Check total memory requests
2. Optimize memory requests/limits
3. Consider scaling cluster

### Step 5: Verify All Pods Running

After fixes:
```bash
kubectl get pods
# Should see all pods in Running state
```

## Quick Commands

```bash
# Check pod status
kubectl get pods

# Check for OOM
kubectl get pods | grep -i oom

# Check node memory
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check specific pod
kubectl describe pod <pod-name>

# View logs
kubectl logs <pod-name>
```

## Expected Issues to Address

1. **OOMKilled pods** - Need to increase memory limits
2. **CrashLoopBackOff** - Check logs, may need more memory
3. **ContainerCreating** - May be waiting for memory/resources
4. **Node memory pressure** - Optimize requests/limits

Let's start by running the audit!

