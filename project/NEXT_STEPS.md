# Next Steps - Deployment Guide

**Last Updated:** $(date)
**Status:** Ready to deploy after completing ConfigMap setup

## Quick Overview

You're almost ready to deploy! Here's what you need to do in order:

1. ✅ **Create ConfigMaps** (5 minutes)
2. ✅ **Verify GCP Project ID** (1 minute)
3. ✅ **Deploy to GKE** (15-20 minutes)
4. ✅ **Verify Deployment** (5 minutes)
5. ✅ **Run Load Tests** (10-15 minutes)

---

## Step 1: Create ConfigMaps ⚠️ **DO THIS FIRST**

The nginx-thrift gateway requires configuration files, Lua scripts, and HTML pages. We've created a script to automate this.

### Option A: Use the Automated Script (Recommended)

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# Make sure kubectl is configured to connect to your cluster
# (The script will check this for you)

# Run the ConfigMap creation script
./scripts/setup-configmaps.sh
```

This script will:
- Verify DeathStarBench source exists
- Create `deathstarbench-config` ConfigMap with all config files
- Create `nginx-lua-scripts` ConfigMap with API handlers
- Create `nginx-pages` ConfigMap with HTML/JS/CSS
- Create `nginx-gen-lua` ConfigMap with Thrift-generated files

### Option B: Manual Creation (if script doesn't work)

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/socialNetwork

# Create main config ConfigMap
kubectl create configmap deathstarbench-config \
  --from-file=service-config.json=config/service-config.json \
  --from-file=jaeger-config.yml=config/jaeger-config.yml \
  --from-file=nginx.conf=nginx-web-server/conf/nginx.conf \
  --from-file=jaeger-config.json=nginx-web-server/jaeger-config.json

# Create Lua scripts ConfigMap
kubectl create configmap nginx-lua-scripts \
  --from-file=nginx-web-server/lua-scripts/

# Create pages ConfigMap
kubectl create configmap nginx-pages \
  --from-file=nginx-web-server/pages/

# Create generated Lua files ConfigMap
kubectl create configmap nginx-gen-lua \
  --from-file=gen-lua/
```

### Verify ConfigMaps Created

```bash
kubectl get configmaps

# You should see:
# - deathstarbench-config
# - nginx-lua-scripts
# - nginx-pages
# - nginx-gen-lua

# Check details
kubectl describe configmap deathstarbench-config
```

---

## Step 2: Verify GCP Project Configuration

Before deploying, make sure your GCP project ID is correct in the deployment files.

### Check Your Current Project ID

```bash
gcloud config get-value project
```

### Update Deployment Files (if needed)

If your project ID is different from `cse239-479821`, update the image references:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# Find files with hardcoded project ID
grep -r "cse239-479821" kubernetes/deployments/

# Replace with your project ID (example for project-id "my-project")
find kubernetes/deployments -name "*.yaml" -exec sed -i '' 's/cse239-479821/my-project/g' {} \;
```

**Note:** The `deploy-gke.sh` script will automatically update image references, but you should verify your project ID is correct.

---

## Step 3: Set Up GKE Cluster (if not already done)

### Create GKE Cluster

```bash
# Set variables
PROJECT_ID=$(gcloud config get-value project)
CLUSTER_NAME="social-network-cluster"
ZONE="us-central1-a"

# Create cluster (adjust machine type and node count as needed)
gcloud container clusters create ${CLUSTER_NAME} \
  --zone=${ZONE} \
  --machine-type=e2-standard-4 \
  --num-nodes=3 \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=5 \
  --project=${PROJECT_ID}

# Get credentials
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}
```

### Verify Cluster Access

```bash
kubectl get nodes
# Should show your cluster nodes
```

---

## Step 4: Deploy to GKE

### Option A: Use the Deployment Script (Recommended)

The script handles everything automatically:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# Set environment variables (optional)
export GKE_CLUSTER="social-network-cluster"
export GKE_ZONE="us-central1-a"
export IMAGE_TAG="latest"

# Run deployment
./scripts/deploy-gke.sh
```

The script will:
1. ✅ Check prerequisites (gcloud, kubectl, docker)
2. ✅ Authenticate with GCP
3. ✅ Create Artifact Registry repository
4. ✅ Pull and push Docker images
5. ✅ Create namespaces
6. ✅ Deploy ConfigMaps (you should have done this in Step 1)
7. ✅ Deploy databases
8. ✅ Deploy microservices
9. ✅ Deploy gateway (nginx-thrift)
10. ✅ Deploy autoscaling configurations
11. ✅ Deploy monitoring (Prometheus, Grafana)

### Option B: Manual Deployment

If you prefer to deploy manually:

```bash
# 1. Set up authentication
gcloud auth configure-docker us-central1-docker.pkg.dev

# 2. Deploy ConfigMaps (you should have done this in Step 1)
kubectl apply -f kubernetes/configmaps/

# 3. Deploy Services (lightweight, create endpoints)
kubectl apply -f kubernetes/services/

# 4. Deploy Databases (they take time to initialize)
kubectl apply -f kubernetes/deployments/databases/
kubectl apply -f kubernetes/services/all-databases.yaml

# 5. Wait for databases to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/user-mongodb-deployment || true

# 6. Deploy Microservices
kubectl apply -f kubernetes/deployments/*.yaml

# 7. Deploy Gateway
kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml

# 8. Deploy Autoscaling
kubectl apply -f kubernetes/autoscaling/

# 9. Deploy Monitoring
kubectl apply -f kubernetes/monitoring/
```

---

## Step 5: Verify Deployment

### Check Pod Status

```bash
# Check all pods
kubectl get pods

# Watch pods (will auto-update)
kubectl get pods -w

# Check specific deployments
kubectl get deployments

# Check if all pods are running
kubectl get pods | grep -v Running | grep -v Completed
```

### Check Service Endpoints

```bash
# Get LoadBalancer IP for nginx-thrift (gateway)
kubectl get service nginx-thrift-service

# Get LoadBalancer IP for Grafana
kubectl get service nginx-thrift-service

# Get all services
kubectl get services
```

### Check Pod Logs

```bash
# Check nginx-thrift logs (gateway)
kubectl logs -l app=nginx-thrift --tail=50

# Check a specific service
kubectl logs -l app=user-service --tail=50

# Check database logs
kubectl logs -l app=user-mongodb --tail=50
```

### Test the API

Once you have the LoadBalancer IP:

```bash
# Get the IP
NGINX_IP=$(kubectl get service nginx-thrift-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test registration endpoint
curl -X POST http://${NGINX_IP}:8080/wrk2-api/user/register \
  -d "user_id=1&username=testuser&first_name=Test&last_name=User&password=testpass"

# Test compose post
curl -X POST http://${NGINX_IP}:8080/wrk2-api/post/compose \
  -d "user_id=1&username=testuser&post_type=0&text=Hello World"
```

---

## Step 6: Run Load Tests with k6

### Install k6 (if not installed)

```bash
# macOS
brew install k6

# Linux
# See: https://k6.io/docs/getting-started/installation/
```

### Get Service Endpoint

```bash
# Get LoadBalancer IP
NGINX_IP=$(kubectl get service nginx-thrift-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Or use port-forward if LoadBalancer isn't ready
kubectl port-forward svc/nginx-thrift-service 8080:8080
# Then use BASE_URL=http://localhost:8080
```

### Run Tests

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# Constant load test
export BASE_URL="http://${NGINX_IP}:8080"
k6 run k6-tests/constant-load.js

# Or use the test runner script
./scripts/run-k6-tests.sh constant-load
```

### Monitor During Tests

In another terminal:

```bash
# Watch pod scaling (HPA)
kubectl get hpa -w

# Watch pod count
kubectl get pods -w

# Watch resource usage
kubectl top pods
```

---

## Step 7: Access Monitoring Dashboards

### Grafana Dashboard

```bash
# Get LoadBalancer IP
GRAFANA_IP=$(kubectl get service grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Or port-forward
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Access at: http://localhost:3000
# Default credentials: admin/admin
```

### Prometheus

```bash
# Port-forward (Prometheus uses ClusterIP by default)
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# Access at: http://localhost:9090
```

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Common issues:
# - ConfigMap not found → Run setup-configmaps.sh
# - Image pull error → Check image registry permissions
# - Database not ready → Wait for databases to initialize
```

### nginx-thrift Pod Failing

```bash
# Check logs
kubectl logs -l app=nginx-thrift

# Common issues:
# - Missing Lua scripts → Verify nginx-lua-scripts ConfigMap exists
# - Missing pages → Verify nginx-pages ConfigMap exists
# - nginx.conf error → Check nginx.conf in deathstarbench-config ConfigMap
```

### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints

# Check if pods are selected by service
kubectl get pods -l app=nginx-thrift

# Check LoadBalancer status
kubectl get service nginx-thrift-service
```

### Database Connection Issues

```bash
# Check if databases are running
kubectl get pods | grep -E "mongodb|redis|memcached"

# Check database logs
kubectl logs <database-pod-name>

# Verify service-config.json has correct service names
kubectl get configmap deathstarbench-config -o yaml
```

---

## Cleanup (When Done Testing)

```bash
# Delete all resources
kubectl delete -f kubernetes/

# Or delete specific components
kubectl delete -f kubernetes/deployments/
kubectl delete -f kubernetes/services/
kubectl delete -f kubernetes/configmaps/

# Delete cluster (if you want to remove everything)
gcloud container clusters delete social-network-cluster --zone=us-central1-a
```

---

## Next: Autoscaling Experiments

Once everything is working, you can run autoscaling experiments:

```bash
# See autoscaling guide
cat AUTOSCALING_GUIDE.md

# Run autoscaling experiments
./scripts/run-autoscaling-experiments.sh
```

---

## Quick Reference

```bash
# Most common commands
kubectl get pods                    # Check pod status
kubectl get services                # Check service endpoints
kubectl logs <pod-name>             # View pod logs
kubectl describe pod <pod-name>     # Debug pod issues
kubectl get configmaps              # Verify ConfigMaps
kubectl get hpa                     # Check autoscaling
```

---

## Need Help?

- Check `TROUBLESHOOTING.md` for common issues
- Review `STATUS_REPORT.md` for current status
- Check `DEATHSTARBENCH_MIGRATION.md` for migration details
- Review Kubernetes logs: `kubectl logs <pod-name>`

Good luck! 🚀

