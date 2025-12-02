# CPU Exhaustion Fix Guide

## Problem Identified ✅

**Root Cause:** Your single node is **99% CPU utilized** (1918m/1930m). There's not enough CPU left to schedule new pods.

## Solution Options (Choose One)

### Option 1: Clean Up Old Pods First (Quick Fix - Try This First)

Many pods are still running from old deployments. Let's free up resources:

```bash
# Delete old pods that are still running (but from old deployments)
kubectl delete pod $(kubectl get pods | grep -E "Running|CrashLoopBackOff" | grep -v "4h\|5h" | awk '{print $1}')

# Actually, better: Delete pods that are from old replica sets
# Check which pods are from old deployments
kubectl get pods -o wide | grep -E "mongodb|redis|memcached"
```

### Option 2: Scale Up Cluster (Best Long-term Solution)

Add more nodes so you have CPU capacity:

```bash
# Check current cluster size
gcloud container clusters describe social-network-cluster --zone=us-central1-a --format="get(currentNodeCount)"

# Scale up cluster (add more nodes)
gcloud container clusters resize social-network-cluster \
  --num-nodes=2 \
  --zone=us-central1-a

# Wait for new node to be ready
kubectl get nodes -w
```

### Option 3: Reduce Resource Requests (Quick Fix)

Reduce CPU requests for pods that don't need as much:

```bash
# Reduce CPU requests for non-critical pods
# This is a quick fix but may impact performance
```

### Option 4: Delete Unnecessary Resources

Check what's consuming CPU:

```bash
# See which pods are using most resources
kubectl top pods --sort-by=cpu

# Delete old/crashed pods that aren't needed
kubectl delete pod $(kubectl get pods | grep CrashLoopBackOff | awk '{print $1}')
```

## Recommended Step-by-Step Fix

### Step 1: Clean Up Old/Crashed Pods

```bash
# Delete all pods in CrashLoopBackOff (they're using resources but not working)
kubectl delete pod $(kubectl get pods | grep CrashLoopBackOff | awk '{print $1}')

# This should free up some CPU immediately
```

### Step 2: Check CPU Usage After Cleanup

```bash
# Wait a moment for cleanup
sleep 5

# Check available CPU
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Step 3: If Still Not Enough CPU, Scale Up

```bash
# Add one more node (this will give you ~1930m more CPU)
gcloud container clusters resize social-network-cluster \
  --num-nodes=2 \
  --zone=us-central1-a
```

### Step 4: Verify Pods Can Schedule

```bash
# Watch pods start
kubectl get pods -w
```

## Quick Fix Command (All in One)

```bash
# Clean up old pods first
kubectl delete pod $(kubectl get pods | grep CrashLoopBackOff | awk '{print $1}')

# Wait and check
sleep 10
kubectl describe nodes | grep -A 5 "Allocated resources"

# If still 99%, scale up
gcloud container clusters resize social-network-cluster \
  --num-nodes=2 \
  --zone=us-central1-a
```

