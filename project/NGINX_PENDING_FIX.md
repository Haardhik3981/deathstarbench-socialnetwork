# Fix nginx-thrift Pods Stuck in Pending

## Problem

nginx-thrift pods are stuck in Pending state even after scaling to 2 nodes.

## Diagnosis

Run this to see why:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/check-pending-nginx.sh
```

Or manually:

```bash
# Check why a specific pod is pending
PENDING_POD=$(kubectl get pods | grep nginx-thrift | grep Pending | head -1 | awk '{print $1}')
kubectl describe pod "$PENDING_POD" | grep -A 20 "Events:"

# Check node CPU usage
kubectl describe nodes | grep -A 5 "Allocated resources"
```

## Possible Causes

### 1. Nodes Still Full (Most Likely)

Even with 2 nodes, if you have many services running, CPU might still be constrained.

**Check:**
```bash
kubectl describe nodes | grep -A 5 "Allocated resources"
```

**Fix:**
- Scale to 3 nodes, OR
- Reduce resource requests for some pods, OR
- Wait a bit longer (some pods may free up resources)

### 2. Image Pull Issues

If the image is large, pulling can take time.

**Check:**
```bash
kubectl describe pod <nginx-pod> | grep -i "pulling\|pull\|image"
```

### 3. PVC Still Waiting

Less likely, but check if there are volume issues.

## Quick Fixes

### Option A: Scale to 3 Nodes (Recommended)

```bash
gcloud container clusters resize social-network-cluster \
  --num-nodes=3 \
  --zone=us-central1-a

# Wait 2-5 minutes
kubectl get nodes -w
```

### Option B: Reduce nginx-thrift Resource Requests

If nodes are close to full, temporarily reduce nginx resource requests:

```bash
kubectl patch deployment nginx-thrift-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx-thrift","resources":{"requests":{"cpu":"50m","memory":"64Mi"}}}]}}}}'
```

### Option C: Wait and Check Resource Availability

Sometimes pods take time to schedule as other pods free up:

```bash
# Check current CPU usage
kubectl describe nodes | grep -A 5 "Allocated resources"

# If nodes have some free CPU, just wait - pods will schedule when resources free up
```

## Recommended Action

1. **First, check why pending:**
   ```bash
   ./scripts/check-pending-nginx.sh
   ```

2. **Based on output:**
   - If CPU > 90% on both nodes → Scale to 3 nodes
   - If CPU < 90% → Wait, pods should schedule soon
   - If other errors → Fix those issues

3. **Scale if needed:**
   ```bash
   gcloud container clusters resize social-network-cluster --num-nodes=3 --zone=us-central1-a
   ```

## Expected Timeline

- Checking status: 30 seconds
- Scaling to 3 nodes: 2-5 minutes
- Pods scheduling: 1-2 minutes after nodes ready
- **Total: ~5-8 minutes**

