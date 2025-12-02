# Monitoring Pod Permission Fix

## Problem

Both Prometheus and Grafana pods were crashing with permission errors:

- **Prometheus**: `permission denied` when trying to write to `/prometheus/queries.active`
- **Grafana**: `/var/lib/grafana` is not writable, cannot create `/var/lib/grafana/plugins`

## Root Cause

The PersistentVolumeClaims (PVCs) were created with incorrect file ownership. The containers run as non-root users:
- Prometheus runs as UID 65534 (nobody user)
- Grafana runs as UID 472 (grafana user)

But the PVCs were mounted with root ownership, preventing the containers from writing to them.

## Solution

### 1. Added `securityContext` to Deployments

Both deployment YAMLs now include `securityContext` in the pod spec:

**Prometheus** (`kubernetes/monitoring/prometheus-deployment.yaml`):
```yaml
securityContext:
  fsGroup: 65534  # Set group ownership on mounted volumes
  runAsUser: 65534
  runAsGroup: 65534
```

**Grafana** (`kubernetes/monitoring/grafana-deployment.yaml`):
```yaml
securityContext:
  fsGroup: 472  # Set group ownership on mounted volumes
  runAsUser: 472
  runAsGroup: 472
```

The `fsGroup` setting ensures that when volumes are mounted, they are owned by the specified group, allowing the containers to write to them.

### 2. Fix Existing PVCs

To fix the existing corrupted PVCs, run:

```bash
./scripts/fix-monitoring-permissions.sh
```

This script will:
1. Scale down both deployments
2. Delete the existing PVCs (⚠️ **This deletes existing metrics data!**)
3. Apply the updated deployments (with securityContext)
4. Scale deployments back up
5. New PVCs will be created with correct permissions

## What This Means

- **Going Forward**: New PVCs will automatically have correct permissions thanks to `fsGroup`
- **Existing Data**: The fix script deletes old PVCs, so you'll lose historical metrics data
- **For Production**: Consider backing up Prometheus data before running the fix, or use a volume snapshot

## Verification

After running the fix script, check pod status:

```bash
kubectl get pods -n monitoring
```

Both pods should be `Running` and `1/1 Ready`. Check logs if issues persist:

```bash
kubectl logs -n monitoring -l app=prometheus --tail=50
kubectl logs -n monitoring -l app=grafana --tail=50
```

## Prevention

The `securityContext` with `fsGroup` is now part of the deployment YAMLs, so this issue won't recur when:
- Deploying fresh clusters
- Recreating PVCs
- Using the `deploy-everything.sh` script

