# Scripts Updated for Fresh Deployment

## Summary

All scripts have been updated to ensure that running `cleanup-everything.sh` followed by `deploy-everything.sh` and `setup-monitoring.sh` will result in a fully working deployment with:
- ✅ All pods running correctly
- ✅ No duplicate pods
- ✅ Monitoring working with proper permissions
- ✅ Clean slate every time

## Changes Made

### 1. `setup-monitoring.sh` - Enhanced Cleanup

**New Function**: `cleanup_existing_monitoring()`
- Automatically scales down existing Prometheus and Grafana deployments
- Deletes old ReplicaSets to prevent duplicate pods
- Cleans up any orphaned pods
- Warns if existing PVCs are found (may have permission issues)
- Ensures clean deployment every time

**Key Features**:
- Runs before deploying new resources
- Prevents the duplicate pod issue we encountered
- Handles both fresh deployments and re-deployments

### 2. `cleanup-everything.sh` - Complete Cleanup

**New Step**: Step 7 - Clean up monitoring namespace
- Deletes all deployments in monitoring namespace
- Deletes all services in monitoring namespace
- Deletes all ConfigMaps in monitoring namespace
- Deletes all PVCs in monitoring namespace (including metrics data)
- Deletes all ReplicaSets in monitoring namespace
- Deletes all pods in monitoring namespace
- Deletes RBAC resources (ServiceAccounts, ClusterRoles, ClusterRoleBindings)

**Additional Improvements**:
- Checks all namespaces when reporting remaining resources
- Better status reporting across namespaces
- Clearer instructions for next steps

### 3. Deployment YAMLs - Permission Fixes

**Already Fixed**:
- `prometheus-deployment.yaml`: Added `securityContext` with `fsGroup: 65534`
- `grafana-deployment.yaml`: Added `securityContext` with `fsGroup: 472`

These fixes ensure that PVCs are created with correct file permissions from the start.

### 4. `deployment-guide.md` - Updated Documentation

**Updated Sections**:
- Monitoring setup instructions now mention cleanup functionality
- Troubleshooting section includes permission error fixes
- Clean start section mentions monitoring namespace cleanup
- Clear deployment order: app first, then monitoring

## Deployment Workflow

### Recommended Order

```bash
# 1. Clean everything (including monitoring)
./cleanup-everything.sh

# 2. Deploy the application
./deploy-everything.sh

# 3. Set up monitoring
./scripts/setup-monitoring.sh
```

### What Happens Now

1. **`cleanup-everything.sh`**:
   - Deletes ALL application resources
   - Deletes ALL monitoring resources
   - Provides clean slate

2. **`deploy-everything.sh`**:
   - Creates ConfigMaps (including nginx-lua-scripts)
   - Deploys databases, caches, services, gateway
   - Everything works as before

3. **`setup-monitoring.sh`**:
   - Cleans up any leftover monitoring resources (prevents duplicates)
   - Deploys Prometheus with correct permissions
   - Deploys Grafana with correct permissions
   - PVCs are created with correct ownership via `fsGroup`

## Verification

After running all three scripts, verify:

```bash
# Check application pods (should all be Running)
kubectl get pods

# Check monitoring pods (should all be Running)
kubectl get pods -n monitoring

# Verify no duplicates
kubectl get pods -n monitoring | grep -E "(prometheus|grafana)" | wc -l
# Should show 2 (1 Prometheus, 1 Grafana)

# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit: http://localhost:9090

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Visit: http://localhost:3000 (admin/admin)
```

## Key Improvements

✅ **No more duplicate pods**: Cleanup functions remove old ReplicaSets
✅ **No more permission errors**: `securityContext` with `fsGroup` fixes PVC permissions
✅ **Idempotent**: Scripts can be run multiple times safely
✅ **Complete cleanup**: `cleanup-everything.sh` now handles monitoring namespace
✅ **Automatic fixes**: `setup-monitoring.sh` handles cleanup automatically

## Troubleshooting

If you still encounter issues:

1. **Duplicate pods**: Run `setup-monitoring.sh` again (it cleans up duplicates)
2. **Permission errors**: Delete PVCs manually, then run `setup-monitoring.sh`:
   ```bash
   kubectl delete pvc prometheus-pvc grafana-pvc -n monitoring
   ./scripts/setup-monitoring.sh
   ```
3. **Stuck pods**: Check events and logs:
   ```bash
   kubectl describe pod -n monitoring <pod-name>
   kubectl logs -n monitoring <pod-name>
   ```

