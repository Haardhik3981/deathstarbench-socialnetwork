# Deployment Guide - DeathStarBench Social Network on GKE

## Overview

This guide walks you through deploying the DeathStarBench Social Network application to Google Kubernetes Engine (GKE), setting up monitoring with Prometheus and Grafana, and running load tests with k6.

## Prerequisites

### Required Tools
- **kubectl** CLI installed
- **gcloud** CLI installed (for GKE)
- **k6** installed (for load testing)
- Access to a GCP project with billing enabled

### Required Resources
- **GKE Cluster**: At least 3 nodes (recommended: `e2-standard-2` or larger)
- **DeathStarBench Source**: The DeathStarBench social network source code
  - Expected location: `../socialNetwork/` relative to this project

### GKE Cluster Setup

If you haven't created a GKE cluster yet:

```bash
# Set your GCP project
export GCP_PROJECT_ID="your-project-id"
gcloud config set project ${GCP_PROJECT_ID}

# Create GKE cluster (recommended: 3 nodes for this deployment)
gcloud container clusters create deathstarbench-cluster \
  --num-nodes=3 \
  --machine-type=e2-standard-2 \
  --zone=us-central1-a \
  --project=${GCP_PROJECT_ID}

# Get credentials
gcloud container clusters get-credentials deathstarbench-cluster \
  --zone=us-central1-a \
  --project=${GCP_PROJECT_ID}

# Verify connection
kubectl cluster-info
```

## Quick Start (Recommended)

### Deploy Everything at Once

The easiest way to deploy everything is using the automated script:

```bash
cd /path/to/deathstarbench-socialnetwork/project

# Make sure you have kubectl connected to your GKE cluster
kubectl cluster-info

# Run the deployment script (this does everything!)
./deploy-everything.sh
```

This script will:
1. ✅ Check prerequisites
2. ✅ Create all ConfigMaps (including nginx-lua-scripts)
3. ✅ Deploy all databases (MongoDB)
4. ✅ Deploy all caches (Redis, Memcached)
5. ✅ Deploy all microservices (11 services)
6. ✅ Deploy Jaeger (tracing)
7. ✅ Deploy nginx-thrift gateway
8. ✅ Create all Kubernetes Services
9. ✅ Show final status

**Expected Duration**: 5-10 minutes

### Verify Deployment

After the script completes, check that all pods are running:

```bash
# Check all pods
kubectl get pods

# You should see:
# - 6 MongoDB pods (Running)
# - 7 cache pods (Redis/Memcached) (Running)
# - 11 microservice pods (Running)
# - 1 Jaeger pod (Running)
# - 1 nginx-thrift pod (Running)

# Check services
kubectl get svc

# Check that nginx-thrift service has an external IP (may take 1-2 minutes)
kubectl get svc nginx-thrift-service
```

### Access the Application

**Option 1: LoadBalancer IP** (recommended for GKE)

```bash
# Get the LoadBalancer IP (may take 1-2 minutes to provision)
NGINX_IP=$(kubectl get svc nginx-thrift-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Application available at: http://${NGINX_IP}:8080"
```

**Option 2: Port-Forward** (for testing)

```bash
# In one terminal, start port-forward
kubectl port-forward svc/nginx-thrift-service 8080:8080

# Then access at: http://localhost:8080
```

## Step-by-Step Manual Deployment

If you prefer to understand each step, you can deploy manually:

### Step 1: Create ConfigMaps

ConfigMaps store configuration files that pods need:

```bash
cd /path/to/deathstarbench-socialnetwork/project
DSB_ROOT="../socialNetwork"

# Main configuration
kubectl create configmap deathstarbench-config \
  --from-file=service-config.json="${DSB_ROOT}/config/service-config.json" \
  --from-file=jaeger-config.yml="${DSB_ROOT}/config/jaeger-config.yml" \
  --from-file=nginx.conf="${DSB_ROOT}/nginx-web-server/conf/nginx.conf" \
  --from-file=jaeger-config.json="${DSB_ROOT}/nginx-web-server/jaeger-config.json"

# Pages (HTML/JS/CSS)
kubectl create configmap nginx-pages --from-file="${DSB_ROOT}/nginx-web-server/pages/"

# Generated Lua files
kubectl create configmap nginx-gen-lua --from-file="${DSB_ROOT}/gen-lua/"

# Lua scripts (requires special handling for subdirectories)
./scripts/fix-nginx-lua-scripts.sh
```

### Step 2: Deploy Databases

```bash
# Deploy all MongoDB databases
for db in media-mongodb post-storage-mongodb social-graph-mongodb \
          url-shorten-mongodb user-mongodb user-timeline-mongodb; do
  kubectl apply -f kubernetes/deployments/databases/${db}-deployment.yaml
done

# Wait for databases to start
sleep 30
```

### Step 3: Deploy Caches

```bash
# Deploy Redis
kubectl apply -f kubernetes/deployments/databases/redis-deployments.yaml

# Deploy Memcached
kubectl apply -f kubernetes/deployments/databases/memcached-deployments.yaml

sleep 20
```

### Step 4: Deploy Microservices

```bash
# Deploy all 11 microservices
for service in compose-post-service home-timeline-service media-service \
              post-storage-service social-graph-service text-service \
              unique-id-service url-shorten-service user-mention-service \
              user-timeline-service user-service; do
  kubectl apply -f kubernetes/deployments/${service}-deployment.yaml
done

sleep 30
```

### Step 5: Deploy Supporting Services

```bash
# Deploy Jaeger
kubectl apply -f kubernetes/deployments/jaeger-deployment.yaml

# Deploy nginx-thrift gateway
kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml

sleep 30
```

### Step 6: Deploy Kubernetes Services

```bash
# Deploy all Service objects (for networking)
for service_file in kubernetes/services/*.yaml; do
  kubectl apply -f "$service_file"
done
```

## Setting Up Monitoring (Prometheus & Grafana)

Monitoring is essential for understanding system performance and identifying bottlenecks during load testing.

### Deploy Monitoring Stack

Use the monitoring setup script:

```bash
cd /path/to/deathstarbench-socialnetwork/project

# Deploy Prometheus and Grafana
./scripts/setup-monitoring.sh
```

This script will:
1. ✅ Create `monitoring` namespace
2. ✅ Clean up any existing monitoring resources (prevents duplicates)
3. ✅ Deploy Prometheus with Kubernetes service discovery (with proper permissions)
4. ✅ Deploy Grafana with Prometheus as data source (with proper permissions)
5. ✅ Set up persistent storage for metrics (with correct file permissions)
6. ✅ Configure RBAC permissions

**Note**: 
- Prometheus and Grafana pods may take 1-2 minutes to start
- The script automatically handles cleanup of old deployments/ReplicaSets to prevent duplicates
- PVC permissions are automatically fixed using `securityContext` with `fsGroup`

### Access Prometheus

**Option 1: Port-Forward** (recommended)

```bash
# In one terminal, start port-forward
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Then access: http://localhost:9090
```

**Option 2: Change Service to LoadBalancer** (if you want external access)

```bash
# Edit the service (not recommended for production)
kubectl edit svc prometheus -n monitoring
# Change type: ClusterIP to type: LoadBalancer
```

### Access Grafana

**Option 1: Port-Forward** (recommended)

```bash
# In another terminal, start port-forward
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Then access: http://localhost:3000
# Default credentials: admin/admin
```

**Option 2: LoadBalancer** (if configured)

```bash
# Get LoadBalancer IP
GRAFANA_IP=$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Grafana available at: http://${GRAFANA_IP}:3000"
```

### Verify Prometheus is Scraping Metrics

1. Access Prometheus UI: http://localhost:9090 (after port-forward)
2. Go to **Status > Targets**: http://localhost:9090/targets
3. You should see targets with status "UP":
   - `prometheus` (Prometheus itself)
   - `kubernetes-pods` (services that expose HTTP metrics)
   - `kubernetes-nodes` (node metrics via API proxy)
   - `cadvisor` (container metrics for all pods)
   - `kubernetes-apiservers` (API server metrics)

**Note:** DeathStarBench microservices will NOT appear in targets because they use Thrift (not HTTP). You can still monitor them using cAdvisor container metrics (CPU, memory, network).

**Important:** The endpoint links in the Targets page will show "site can't be reached" in your browser - this is **normal and expected**. These are internal Kubernetes addresses that only work from within the cluster. Prometheus can access them, which is what matters.

### Using Prometheus

**For a complete guide on how to use Prometheus, see:** `PROMETHEUS_GUIDE.md`

**Quick Start:**
1. **Check Targets Page** (Status > Targets) - Verify services are UP
2. **Query Metrics** (Graph page) - Type queries like:
   - `container_cpu_usage_seconds_total` - See CPU usage
   - `container_memory_usage_bytes` - See memory usage
   - `rate(container_cpu_usage_seconds_total[5m])` - CPU usage rate
3. **Monitor During Tests** - Watch metrics change in real-time during k6 load tests

### Configure Grafana Dashboards

1. Access Grafana: http://localhost:3000
2. Login with: `admin/admin` (change password on first login)
3. Prometheus should already be configured as a data source
4. Create dashboards or import pre-built Kubernetes dashboards:
   - Go to **Dashboards > Import**
   - Search for "Kubernetes" dashboards
   - Recommended: "Kubernetes Cluster Monitoring" (dashboard ID: 7249)

### What Prometheus Monitors

By default, Prometheus automatically discovers and scrapes:

- **All Kubernetes pods** (with `prometheus.io/scrape=true` annotation)
- **Kubernetes nodes** (CPU, memory, network stats via cAdvisor)
- **Kubernetes API server** (cluster metrics)
- **Microservices** (user-service, social-graph-service, etc.)
- **Prometheus itself**

## Running Load Tests with k6

Before running load tests, make sure monitoring is set up so you can observe system behavior.

### Prerequisites for k6

```bash
# Install k6 (macOS)
brew install k6

# Or download from: https://k6.io/docs/getting-started/installation/
```

### Run Load Tests

**If using port-forward for nginx-thrift:**

```bash
# Terminal 1: Keep port-forward running
kubectl port-forward svc/nginx-thrift-service 8080:8080

# Terminal 2: Run k6 test
cd /path/to/deathstarbench-socialnetwork/project
BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh constant-load
```

**If using LoadBalancer IP:**

```bash
# The script will auto-detect the LoadBalancer IP
./scripts/run-k6-tests.sh constant-load

# Or set manually
BASE_URL=http://<LOADBALANCER_IP>:8080 ./scripts/run-k6-tests.sh constant-load
```

### Available Test Types

1. **constant-load** - Steady load test (recommended to start)
   - Duration: ~7 minutes
   - Simulates 50 virtual users
   - Tests baseline performance

2. **peak-test** - Sudden traffic spike
   - Tests system behavior under sudden load

3. **stress-test** - Gradual ramp-up
   - Finds breaking point
   - Useful for capacity planning

4. **endurance-test** - Long-duration test
   - Runs for 5+ hours
   - Tests for memory leaks and stability

5. **all** - Run all tests (except endurance)

### Monitoring During Tests

While k6 tests run:

1. **Watch Prometheus Metrics**:
   - Open: http://localhost:9090
   - Run queries like:
     - `rate(http_requests_total[1m])` - Request rate
     - `http_request_duration_seconds` - Response times
     - `container_cpu_usage_seconds_total` - CPU usage

2. **Watch Grafana Dashboards**:
   - Open: http://localhost:3000
   - Monitor CPU, memory, network metrics
   - Watch for bottlenecks

3. **Watch Pod Status**:
   ```bash
   # In another terminal
   watch kubectl get pods
   ```

### Test Results

Results are saved to `k6-results/` directory:
- JSON files with detailed metrics
- Summary files with key statistics

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Check events
kubectl get events --sort-by='.lastTimestamp'
```

### nginx-thrift Not Working

```bash
# Check pod logs
kubectl logs -l app=nginx-thrift --tail=100

# Check if ConfigMaps exist
kubectl get configmap nginx-lua-scripts
kubectl get configmap nginx-gen-lua
kubectl get configmap nginx-pages

# Verify ConfigMap has files
kubectl describe configmap nginx-lua-scripts
```

### Prometheus Not Scraping Metrics

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit: http://localhost:9090/targets

# Check Prometheus logs
kubectl logs -n monitoring deployment/prometheus

# Verify RBAC permissions
kubectl get clusterrolebinding prometheus
```

### Grafana Can't Connect to Prometheus

```bash
# Check Grafana logs
kubectl logs -n monitoring deployment/grafana

# Verify Prometheus service is accessible
kubectl run -it --rm debug --image=busybox --restart=Never \
  -- wget -O- http://prometheus.monitoring.svc.cluster.local:9090/-/healthy

# Check datasource configuration
kubectl get configmap grafana-datasources -n monitoring -o yaml
```

### Monitoring Pods Crashing with Permission Errors

If Prometheus or Grafana pods are crashing with permission errors:

```bash
# The setup script should handle this automatically, but if issues persist:
./scripts/fix-monitoring-permissions.sh

# This will delete and recreate PVCs with correct permissions
```

**Note**: The monitoring deployment YAMLs now include `securityContext` with `fsGroup` to automatically fix permissions. This should prevent permission issues in fresh deployments.

### High CPU/Memory Usage

If pods are consuming too many resources:

```bash
# Check resource usage
kubectl top pods
kubectl top nodes

# Scale down if needed (adjust as necessary)
kubectl scale deployment user-service-deployment --replicas=1
```

### Clean Start

If you want to start fresh:

```bash
# Clean everything (including monitoring namespace)
./cleanup-everything.sh

# Deploy the application first
./deploy-everything.sh

# Then set up monitoring
./scripts/setup-monitoring.sh
```

**Note**: The `cleanup-everything.sh` script now also cleans up monitoring namespace resources (Prometheus, Grafana, PVCs, etc.), ensuring a completely clean slate.

## Resource Requirements

### Minimum Cluster Resources

- **Nodes**: 3 nodes minimum
- **Node Type**: `e2-standard-2` (2 vCPU, 8GB RAM per node)
- **Total CPU**: ~6 vCPUs available
- **Total Memory**: ~24GB available

### Per-Component Resources

- **MongoDB**: 100m CPU, 512Mi memory per pod (6 pods)
- **Redis/Memcached**: 50-100m CPU, 64-256Mi memory per pod (7 pods)
- **Microservices**: 100m CPU, 128Mi memory per pod (11 pods)
- **nginx-thrift**: 100m CPU, 128Mi memory (1 pod)
- **Jaeger**: 100m CPU, 256Mi memory (1 pod)
- **Prometheus**: 100m CPU, 256Mi memory (1 pod)
- **Grafana**: 100m CPU, 128Mi memory (1 pod)

**Total**: ~27 pods running

## Next Steps

1. **Run Baseline Tests**: Use `constant-load` to establish baseline metrics
2. **Create Grafana Dashboards**: Customize dashboards for your specific metrics
3. **Set Up Autoscaling**: Configure HPA/VPA based on test results
4. **Monitor Resource Usage**: Use Grafana to identify optimization opportunities
5. **Run Stress Tests**: Find system limits and capacity
6. **Optimize**: Adjust resource requests/limits based on actual usage

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [k6 Documentation](https://k6.io/docs/)
- [DeathStarBench GitHub](https://github.com/delimitrou/DeathStarBench)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)

## Quick Reference Commands

```bash
# Check all pods
kubectl get pods

# Check services
kubectl get svc

# Check ConfigMaps
kubectl get configmap

# Port-forward nginx-thrift
kubectl port-forward svc/nginx-thrift-service 8080:8080

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Port-forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Run k6 test
BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh constant-load

# Clean everything
./cleanup-everything.sh

# Deploy everything
./deploy-everything.sh

# Setup monitoring
./scripts/setup-monitoring.sh
```
