# Step-by-Step Storage Fix Guide

## Current Situation

Your PVCs are all **Pending** with storage class `standard-rwo`. This is why database pods can't start.

## Step 1: Diagnose the Problem

Run this diagnostic script:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/check-storage-step-by-step.sh
```

Or check manually:

```bash
# 1. Check if storage class exists
kubectl get storageclass standard-rwo

# 2. Check why a specific PVC is pending (look at Events section)
kubectl describe pvc user-mongodb-pvc

# 3. List all available storage classes
kubectl get storageclass
```

## Common Issues and Solutions

### Issue A: Storage Class Doesn't Exist

**Symptom:** `Error from server (NotFound): storageclasses.storage.k8s.io "standard-rwo" not found`

**Solution:** Check available storage classes and update PVCs to use an existing one.

**GKE typically has:**
- `standard` - Standard persistent disk (can be default)
- `premium-rwo` - Premium SSD (ReadWriteOnce)
- `premium-rsc` - Premium SSD (ReadWriteSinglePod)

**Fix:**
1. Check what's available:
   ```bash
   kubectl get storageclass
   ```

2. Update PVCs to use an existing storage class. We can either:
   - Delete and recreate PVCs with correct storage class
   - Or patch the deployment files to use correct storage class

### Issue B: Storage Class Exists But Can't Provision

**Symptom:** Storage class exists but PVCs still pending

**Possible causes:**
1. **No default storage class** - Set one as default
2. **Insufficient quota** - GCP project doesn't have enough disk quota
3. **Regional/Zonal mismatch** - Storage class is regional but cluster is zonal (or vice versa)

**Fix for no default:**
```bash
# Check if there's a default storage class
kubectl get storageclass -o json | grep -i "is-default-class"

# If none are default, set one
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Issue C: PVCs Using Wrong Storage Class

**Symptom:** PVCs use `standard-rwo` but GKE has `standard` or `premium-rwo`

**Solution:** Update PVC definitions to use correct storage class.

## Step-by-Step Fix (Based on Diagnosis)

### Option 1: If `standard-rwo` doesn't exist, use `standard` instead

```bash
# Check available storage classes first
kubectl get storageclass

# If 'standard' exists, update PVCs to use it
# We need to edit the database deployment files
```

### Option 2: Set a default storage class

```bash
# If 'standard' exists, set it as default
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Then delete and recreate PVCs (they'll use default)
kubectl delete pvc --all
kubectl apply -f kubernetes/deployments/databases/
```

### Option 3: Update PVC files to use correct storage class

Edit the PVC definitions in database deployment files to use the correct storage class.

## Recommended Action Plan

**First, let's diagnose:**

```bash
# Step 1: Check what storage classes exist
kubectl get storageclass

# Step 2: Check why PVCs are pending
kubectl describe pvc user-mongodb-pvc | tail -30
```

**Then share the output** and I'll tell you exactly which fix to apply.

## Expected Timeline

- **Diagnosis:** 2 minutes
- **Fix:** 2-5 minutes (depending on issue)
- **PVC binding:** 30 seconds - 2 minutes after fix
- **Database pods starting:** 1-3 minutes after PVCs bind

## Don't Worry!

PVCs pending is a **common issue** and usually easy to fix once we know the root cause. The diagnostic will tell us exactly what's wrong.

