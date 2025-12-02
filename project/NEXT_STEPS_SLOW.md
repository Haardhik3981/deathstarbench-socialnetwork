# Next Steps - Slow and Methodical

## Current Situation

You have:
- ✅ Some pods started (with new config mounts)
- ❌ Many pods still **Pending** (CPU constraint)
- ❌ Some pods **Crashing** (need to check if config fix worked or new error)

## Step-by-Step Action Plan

### Step 1: Check Current Status

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/check-current-status.sh
```

This will tell us:
1. If CPU is still the issue
2. If config fix worked (check logs of new crashing pods)
3. How many pods are in each state

### Step 2: Check Why New Pods Are Crashing

We need to see if the config mount fix worked. Check logs:

```bash
# Check logs of a newly started pod (one that crashed recently)
kubectl logs compose-post-service-deployment-79c7c5b8b7-984v4 --tail=50

# Or check another one
kubectl logs post-storage-service-deployment-5c8566f4c-nxzmz --tail=50
```

**What to look for:**
- ✅ If you see **different error** (not YAML::BadFile) → Config fix worked! New issue to fix.
- ❌ If you see **same YAML::BadFile error** → Config fix didn't work, need to investigate.

### Step 3: Address CPU Constraint (Still the Main Issue)

Most pods are still pending due to CPU. You have two options:

#### Option A: Scale Up Cluster (Recommended)

```bash
# Add a second node (gives you ~1930m more CPU)
gcloud container clusters resize social-network-cluster \
  --num-nodes=2 \
  --zone=us-central1-a

# Wait for new node (2-5 minutes)
kubectl get nodes -w
```

#### Option B: Clean Up More Aggressively

```bash
# Delete all duplicate/old pods
# But be careful - we want to keep at least one pod per service
```

### Step 4: After Scaling, Monitor

```bash
# Watch pods start
kubectl get pods -w

# Should see:
# - Pending pods start scheduling
# - PVCs bind (once pods schedule)
# - Pods start running
```

## Recommended Order

1. **First:** Run status check script
2. **Second:** Check logs of crashing pods (see if config fix worked)
3. **Third:** Scale up cluster (fix CPU issue)
4. **Fourth:** Monitor pods starting
5. **Fifth:** Fix any remaining errors found in logs

## Questions to Answer

- [ ] Is CPU still 99%? (run status check)
- [ ] Are new crashing pods showing YAML::BadFile or different error? (check logs)
- [ ] Are there duplicate pods we can clean up? (run status check)

After Step 1 (status check), we'll know exactly what to do next.

