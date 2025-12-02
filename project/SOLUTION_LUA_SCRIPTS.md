# Solution: nginx-lua-scripts ConfigMap Issue

## The Problem

1. ConfigMap keys **cannot contain `/`** characters
2. `kubectl create configmap --from-file` doesn't recursively include subdirectories
3. We need to preserve the directory structure (`api/`, `wrk2-api/`) for nginx

## The Real Solution

Since kubectl can't handle this easily, we have two options:

### Option 1: Use an Init Container (Recommended)

Create a flattened ConfigMap and use an init container to recreate the directory structure.

### Option 2: Create Separate ConfigMaps

Create one ConfigMap per subdirectory and mount them separately (like OpenShift does).

## Quick Fix for Now

Let's try creating from the parent directory - this might work:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/socialNetwork/nginx-web-server

# Create ConfigMap from parent, referencing lua-scripts
kubectl delete configmap nginx-lua-scripts 2>/dev/null
kubectl create configmap nginx-lua-scripts --from-file=lua-scripts/

# Check if it worked
kubectl get configmap nginx-lua-scripts
kubectl get configmap nginx-lua-scripts -o yaml | head -50
```

If that still shows 0 files, we need to use the init container approach.

