# Root Cause Analysis - Why CPU Still High

## The Problem

Even after cleanup and scaling to 3 nodes, CPU is still 98-99% on all nodes. Duplicates still exist.

## Root Cause: Old ReplicaSets

**The issue:** Old ReplicaSets are still alive and recreating pods. Even though deployments have `replicas: 1`, old ReplicaSets from previous deployments still exist and create extra pods.

## Why Cleanup Didn't Work

- Deleting pods doesn't delete ReplicaSets
- ReplicaSets immediately recreate pods to match their desired count
- Multiple ReplicaSets from same deployment can exist (from updates)

## Solution: Delete Old ReplicaSets

### Step 1: Find Old ReplicaSets

```bash
# See all ReplicaSets
kubectl get rs

# Find ones with 0 desired replicas or multiple pods
kubectl get rs | awk 'NR>1 && ($2==0 || $2>1) {print $1}'
```

### Step 2: Delete Old ReplicaSets

```bash
# Use the script
./scripts/delete-old-replicasets.sh

# Or manually delete specific ones
kubectl delete rs <old-rs-name>
```

### Step 3: Force Delete All Extra Pods

```bash
# Get all pods, keep only one per deployment type
# This is more aggressive but necessary
```

## Quick Diagnostic

Run this to see what's happening:

```bash
# See all ReplicaSets
kubectl get rs -o wide

# Count pods per deployment
kubectl get pods | awk '{print $1}' | cut -d'-' -f1-4 | sort | uniq -c | sort -rn

# See which deployments have multiple ReplicaSets
kubectl get rs | awk '{print $1}' | cut -d'-' -f1-4 | sort | uniq -d
```

## Nuclear Option: Delete Old ReplicaSets Manually

If the script doesn't work, manually delete:

```bash
# List all ReplicaSets
kubectl get rs

# For each old one (check age, see if it's from old deployment):
kubectl delete rs <old-rs-name>
```

## Expected Result After Fix

- Service pods: 11 (one per service)
- MongoDB pods: 6 (one per database)
- CPU usage: Should drop significantly
- nginx-thrift: Should be able to schedule

The key is deleting the ReplicaSets, not just the pods!

