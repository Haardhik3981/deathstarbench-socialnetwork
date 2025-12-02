# Quick Fix for nginx-thrift ConfigMap

## The Problem

The `nginx-lua-scripts` ConfigMap has 0 files because the script only looks at the top-level directory, but the Lua files are in subdirectories (`api/` and `wrk2-api/`).

## Quick Fix - Run This

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/fix-nginx-lua-scripts-final.sh
```

## What It Does

1. Finds all `.lua` files in subdirectories
2. Deletes the empty ConfigMap
3. Creates a new ConfigMap with ALL files (including subdirectories)
4. Restarts nginx-thrift

## Verify It Worked

```bash
# Check ConfigMap has files now
kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | python3 -c "import sys, json; print(f'Files: {len(json.load(sys.stdin))}')"

# Or simpler check
kubectl get configmap nginx-lua-scripts

# Watch nginx-thrift start
kubectl get pods -l app=nginx-thrift -w
```

## Expected Result

- ConfigMap should have ~13-15 files (not 0)
- nginx-thrift pod should restart
- Pod should become Ready (1/1) instead of CrashLoopBackOff

Run the script and let me know if it works!

