# Monitoring Setup Tips

## If Setup Script Hangs

If `setup-monitoring.sh` appears to hang while waiting for Prometheus or Grafana:

### Option 1: Let It Continue

The script will automatically continue even if pods take longer than expected. It will:
- Show progress updates every 30 seconds
- Continue to Grafana deployment even if Prometheus isn't fully ready
- Provide diagnostic information at the end

### Option 2: Check Pod Status Manually

In another terminal:

```bash
# Check monitoring pods
kubectl get pods -n monitoring

# Check Prometheus pod specifically
kubectl get pods -n monitoring -l app=prometheus

# Check Grafana pod specifically
kubectl get pods -n monitoring -l app=grafana
```

### Common Issues

#### 1. Pod Stuck in "Pending" State

**Cause**: Usually insufficient resources (CPU/memory)

**Solution**:
```bash
# Check node resources
kubectl top nodes

# Check pod events to see why it's pending
kubectl describe pod <pod-name> -n monitoring

# Common message: "Insufficient cpu" or "Insufficient memory"
# Solution: Scale up cluster or reduce resource requests
```

#### 2. Pod Stuck in "ContainerCreating"

**Cause**: Usually PVC (Persistent Volume) provisioning issue

**Solution**:
```bash
# Check PVC status
kubectl get pvc -n monitoring

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# If PVC is "Pending", check storage class
kubectl get storageclass
```

#### 3. Pod Crashing/Error

**Cause**: Configuration issue or image pull problem

**Solution**:
```bash
# Check pod logs
kubectl logs <pod-name> -n monitoring

# Check previous container logs (if it crashed)
kubectl logs <pod-name> -n monitoring --previous

# Check pod description
kubectl describe pod <pod-name> -n monitoring
```

#### 4. RBAC Permissions Issue

**Cause**: Prometheus ServiceAccount doesn't have proper permissions

**Solution**:
```bash
# Check if ServiceAccount exists
kubectl get serviceaccount prometheus -n monitoring

# Check ClusterRoleBinding
kubectl get clusterrolebinding prometheus

# If missing, reapply the Prometheus deployment
kubectl apply -f kubernetes/monitoring/prometheus-deployment.yaml
```

## Quick Fixes

### Skip Waiting and Check Later

If the script is taking too long, you can:

1. **Interrupt the script** (Ctrl+C) - the deployments are already applied
2. **Check status manually**:
   ```bash
   kubectl get pods -n monitoring
   ```
3. **Port-forward when ready**:
   ```bash
   # Wait for pod to be Running, then:
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   ```

### Verify Monitoring is Working

Once pods are running:

```bash
# Check Prometheus targets (if port-forward is active)
# Visit: http://localhost:9090/targets

# Check Grafana (if port-forward is active)
# Visit: http://localhost:3000
# Login: admin/admin
```

### Restart Monitoring Stack

If things are stuck:

```bash
# Delete and redeploy
kubectl delete deployment prometheus grafana -n monitoring
kubectl delete pvc prometheus-pvc grafana-pvc -n monitoring

# Then run setup script again
./scripts/setup-monitoring.sh
```

## Resource Requirements

Prometheus and Grafana need:
- **Prometheus**: 100m CPU, 256Mi memory (requested)
- **Grafana**: 100m CPU, 128Mi memory (requested)
- **Storage**: 5Gi for Prometheus, 1Gi for Grafana

If your cluster is resource-constrained, the pods may take longer to schedule or may be pending.

## Expected Timeline

- **Pod creation**: Immediate (within seconds)
- **PVC provisioning**: 10-30 seconds (GKE)
- **Container start**: 10-30 seconds
- **Pod ready**: 1-2 minutes total

If pods take longer than 3-4 minutes, check for resource constraints.

