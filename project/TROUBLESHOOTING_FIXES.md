# Troubleshooting Guide - Fixes for Current Issues

## Issue 1: Services Crashing with `YAML::BadFile` Error ✅ FIXED

**Problem:** Services were crashing with error: `terminate called after throwing an instance of 'YAML::BadFile' what(): bad file`

**Root Cause:** The services look for config files at specific paths (`config/jaeger-config.yml` and `config/service-config.json`), but the ConfigMap was mounted as a directory instead of individual files.

**Solution Applied:** ✅ Updated all service deployments to mount config files using `subPath`:

```yaml
volumeMounts:
- name: config
  mountPath: /social-network-microservices/config/jaeger-config.yml
  subPath: jaeger-config.yml
  readOnly: true
- name: config
  mountPath: /social-network-microservices/config/service-config.json
  subPath: service-config.json
  readOnly: true
```

**Action Required:**
```bash
# Redeploy all service deployments (use loop for macOS/zsh compatibility)
for file in kubernetes/deployments/*-service-deployment.yaml; do 
  kubectl apply -f "$file"
done

# Or apply the entire deployments directory (includes databases too)
# kubectl apply -f kubernetes/deployments/

# Watch pods to see if they start successfully
kubectl get pods -w

# Check logs of a service to verify it's working
kubectl logs -l app=user-service --tail=50
```

---

## Issue 2: Many Pods in Pending State ⚠️ NEEDS INVESTIGATION

**Problem:** Many pods (especially databases) are stuck in `Pending` state.

**Possible Causes:**

### A. PersistentVolumeClaims Not Binding

Databases need persistent storage. Check if PVCs are bound:

```bash
# Check PVC status
kubectl get pvc

# Check specific PVC
kubectl describe pvc <pvc-name>

# Common issues:
# - Storage class not available
# - Insufficient storage quota
# - No nodes with available storage
```

**Fix for Storage Issues:**
```bash
# Check if storage class exists
kubectl get storageclass

# If no default storage class, set one:
# GKE usually has standard storage class, but you may need to:
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Or update PVCs to use a specific storage class
# Edit the database deployment YAMLs and add:
# spec:
#   storageClassName: standard
```

### B. Resource Constraints

Pods may be pending due to insufficient CPU/memory:

```bash
# Check node resources
kubectl top nodes

# Check pod resource requests vs available
kubectl describe node <node-name>

# Check if pods are unschedulable
kubectl get pods -o wide
kubectl describe pod <pending-pod-name>
```

**Fix for Resource Issues:**
- Reduce replica count
- Reduce resource requests in deployments
- Add more nodes to cluster
- Increase node size

### C. Node Affinity/Selectors

Check if pods have specific node requirements:

```bash
# Describe a pending pod to see events
kubectl describe pod <pending-pod-name> | grep -A 20 Events

# Common messages:
# - "0/3 nodes are available: 3 Insufficient cpu"
# - "0/3 nodes are available: 3 Insufficient memory"
# - "pod has unbound immediate PersistentVolumeClaims"
```

---

## Issue 3: nginx-thrift Pod Crashing ⚠️ NEEDS CHECKING

**Problem:** nginx-thrift is in CrashLoopBackOff.

**Debug Steps:**
```bash
# Check logs
kubectl logs -l app=nginx-thrift --tail=100

# Check pod events
kubectl describe pod $(kubectl get pods -l app=nginx-thrift | grep CrashLoopBackOff | head -1 | awk '{print $1}')

# Verify ConfigMaps are mounted correctly
kubectl exec -it $(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}') -- ls -la /usr/local/openresty/nginx/
```

**Common Issues:**
1. **Missing Lua scripts** - Verify `nginx-lua-scripts` ConfigMap exists
2. **Missing pages** - Verify `nginx-pages` ConfigMap exists
3. **nginx.conf error** - Check nginx.conf syntax in ConfigMap
4. **Gen-lua path** - May need to add gen-lua to lua_package_path

**Fix for nginx.conf lua_package_path:**
If nginx can't find gen-lua files, update the nginx.conf ConfigMap:

```bash
# Get current nginx.conf
kubectl get configmap deathstarbench-config -o jsonpath='{.data.nginx\.conf}' > nginx.conf.tmp

# Edit nginx.conf.tmp and update lua_package_path line to include:
# lua_package_path '/usr/local/openresty/nginx/lua-scripts/?.lua;/usr/local/openresty/nginx/gen-lua/?.lua;/usr/local/openresty/luajit/share/lua/5.1/?.lua;;';

# Update ConfigMap
kubectl create configmap deathstarbench-config \
  --from-file=nginx.conf=nginx.conf.tmp \
  --from-file=service-config.json=<path-to-service-config.json> \
  --from-file=jaeger-config.yml=<path-to-jaeger-config.yml> \
  --from-file=jaeger-config.json=<path-to-jaeger-config.json> \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart nginx-thrift
kubectl rollout restart deployment/nginx-thrift-deployment
```

---

## Step-by-Step Recovery Plan

### Step 1: Fix Service Deployments (✅ Done)
```bash
# Already completed - services should work after redeploy
# Use loop for macOS/zsh compatibility (glob expansion issue)
for file in kubernetes/deployments/*-service-deployment.yaml; do 
  kubectl apply -f "$file"
done
```

### Step 2: Check PVC Status
```bash
kubectl get pvc
# If any show "Pending", check why:
kubectl describe pvc <pending-pvc-name>
```

### Step 3: Fix Storage Issues (if needed)
```bash
# If storage class issues, check available storage classes
kubectl get storageclass

# GKE should have 'standard' or 'premium-rwo'
# If not, you may need to create PVCs with a different storage class
```

### Step 4: Check Node Resources
```bash
# See if nodes have capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# If nodes are full, consider:
# - Scaling up cluster
# - Reducing resource requests
# - Deleting unused pods
```

### Step 5: Redeploy Everything in Order
```bash
# 1. Delete all deployments to start fresh
kubectl delete deployment --all

# 2. Wait a moment
sleep 5

# 3. Deploy databases first (they need time to initialize)
kubectl apply -f kubernetes/deployments/databases/
kubectl apply -f kubernetes/services/all-databases.yaml

# 4. Wait for databases to be ready (can take 2-5 minutes)
kubectl wait --for=condition=available --timeout=600s deployment/user-mongodb-deployment || true
kubectl wait --for=condition=available --timeout=600s deployment/user-memcached-deployment || true

# 5. Deploy services (with fixed config mounts)
kubectl apply -f kubernetes/deployments/*-service-deployment.yaml

# 6. Deploy gateway
kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml

# 7. Monitor
kubectl get pods -w
```

---

## Quick Diagnostic Commands

```bash
# Overall cluster status
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get pvc

# Check specific issues
kubectl get events --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods

# Check service endpoints
kubectl get endpoints

# Check ConfigMaps
kubectl get configmaps
kubectl describe configmap deathstarbench-config
```

---

## Expected Timeline After Fixes

1. **Service pods** should start within 30-60 seconds after redeploy
2. **Database pods** may take 2-5 minutes to initialize
3. **nginx-thrift** should start within 1-2 minutes
4. **All pods running** should take 5-10 minutes total

---

## Still Having Issues?

If services still crash after fixing config mounts:

1. **Check logs in detail:**
   ```bash
   kubectl logs <pod-name> --previous  # Previous container logs
   kubectl logs <pod-name> -c <container-name>  # Specific container
   ```

2. **Verify ConfigMap contents:**
   ```bash
   kubectl get configmap deathstarbench-config -o yaml | grep -A 50 "jaeger-config.yml"
   ```

3. **Test file access in pod:**
   ```bash
   kubectl exec -it <pod-name> -- ls -la /social-network-microservices/config/
   kubectl exec -it <pod-name> -- cat /social-network-microservices/config/jaeger-config.yml
   ```

4. **Check if services can connect to databases:**
   ```bash
   # From inside a service pod
   kubectl exec -it <service-pod> -- nc -zv user-mongodb 27017
   kubectl exec -it <service-pod> -- nc -zv user-memcached 11211
   ```

Good luck! The config mount fix should resolve most service crashes.

