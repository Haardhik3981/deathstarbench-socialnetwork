# Immediate Actions to Fix Pod Issues

Based on your pod status, you have **two sets of pods**:
1. **Old pods** (4h+ old) - Still crashing with old configuration
2. **New pods** (1-2 minutes old) - Stuck in Pending state

## Quick Diagnosis

Run these commands to understand what's happening:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# Check why pods are pending
./scripts/diagnose-pods.sh

# Or check specific issues
./scripts/fix-pending-pods.sh
```

## Most Likely Issues

### Issue 1: Old Pods Still Running (Need Cleanup)

The old pods with `CrashLoopBackOff` are still consuming resources. Delete them:

```bash
# Delete all old crashing pods
kubectl delete pod $(kubectl get pods | grep CrashLoopBackOff | awk '{print $1}')

# Or delete old pods by deployment
kubectl delete pod user-service-deployment-c97bc7b58-rthq8
kubectl delete pod compose-post-service-deployment-79c7c5b8b7-l5wbq
# ... etc for all old pods
```

### Issue 2: PVCs Not Binding (Storage Issue)

Database pods need persistent storage. Check:

```bash
# Check PVC status
kubectl get pvc

# Check if storage class exists
kubectl get storageclass

# Check why a specific PVC is pending
kubectl describe pvc user-mongodb-pvc
```

**Fix for PVC issues:**
```bash
# If no default storage class, set one
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Or for GKE, try premium-rwo
kubectl patch storageclass premium-rwo -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Issue 3: Resource Constraints

Pods may be pending due to insufficient CPU/memory:

```bash
# Check node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check specific pod why it's pending
kubectl describe pod <pending-pod-name> | grep -A 10 "Events:"
```

**Common messages:**
- `0/X nodes are available: X Insufficient cpu` → Reduce CPU requests or scale cluster
- `0/X nodes are available: X Insufficient memory` → Reduce memory requests or scale cluster
- `pod has unbound immediate PersistentVolumeClaims` → PVC issue (see Issue 2)

## Step-by-Step Recovery

### Step 1: Delete Old Crashing Pods

```bash
# This forces Kubernetes to use the new deployments
kubectl delete pod $(kubectl get pods | grep CrashLoopBackOff | awk '{print $1}')
```

### Step 2: Check Why New Pods Are Pending

```bash
# Check a specific pending pod
PENDING_POD=$(kubectl get pods | grep Pending | head -1 | awk '{print $1}')
kubectl describe pod "$PENDING_POD" | tail -40
```

Look for messages like:
- `pod has unbound immediate PersistentVolumeClaims` → Storage issue
- `0/X nodes are available: X Insufficient cpu` → Resource constraint
- `0/X nodes are available: X Insufficient memory` → Resource constraint

### Step 3: Fix Storage Issues (if PVCs are pending)

```bash
# Check PVCs
kubectl get pvc

# If any are pending, check storage class
kubectl get storageclass

# Set default storage class (GKE usually has 'standard')
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# If PVCs still pending, delete and recreate them
kubectl delete pvc --all
kubectl apply -f kubernetes/deployments/databases/
```

### Step 4: Fix Resource Constraints (if nodes are full)

```bash
# Check node resources
kubectl top nodes

# If nodes are full, you have options:
# Option A: Reduce resource requests in deployments (quick fix)
# Option B: Scale up cluster (add more nodes)
# Option C: Reduce replica counts
```

To reduce resource requests quickly:
```bash
# Edit deployments to reduce requests
# Or use kubectl patch
kubectl patch deployment user-service-deployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"user-service","resources":{"requests":{"cpu":"50m","memory":"64Mi"}}}]}}}}'
```

### Step 5: Monitor Recovery

```bash
# Watch pods start
kubectl get pods -w

# Check logs of new pods once they start
kubectl logs -l app=user-service --tail=50
```

## Quick Commands Reference

```bash
# Delete all old crashing pods
kubectl delete pod $(kubectl get pods | grep CrashLoopBackOff | awk '{print $1}')

# Check PVC status
kubectl get pvc

# Check storage classes
kubectl get storageclass

# Set default storage class
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Check why a pod is pending
kubectl describe pod <pod-name> | tail -40

# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Watch pods
kubectl get pods -w
```

## Expected Outcome

After cleanup:
1. ✅ Old crashing pods deleted
2. ✅ New pods start (may still be pending if storage/resources issue)
3. ✅ If storage fixed: Database pods start
4. ✅ If resources OK: Service pods start
5. ✅ Services connect to databases

## Still Having Issues?

If pods are still pending after cleanup, check the specific error:

```bash
# Get detailed info on a pending pod
PENDING_POD=$(kubectl get pods | grep Pending | head -1 | awk '{print $1}')
kubectl describe pod "$PENDING_POD"
```

Share the "Events:" section output and I can help troubleshoot further.

