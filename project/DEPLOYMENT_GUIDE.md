# Complete Deployment Guide: DeathStarBench on GKE

## For Beginners - Everything Explained

This guide will walk you through deploying the DeathStarBench Social Network application to Google Kubernetes Engine (GKE) from scratch.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Understanding the Architecture](#understanding-the-architecture)
3. [Cluster Setup](#cluster-setup)
4. [Deployment Steps](#deployment-steps)
5. [Memory & Resource Requirements](#memory--resource-requirements)
6. [Common Issues & Fixes](#common-issues--fixes)
7. [Testing Your Deployment](#testing-your-deployment)

---

## Prerequisites

Before you start, make sure you have:

### 1. Google Cloud Account & Project
- A GCP account with billing enabled
- A GCP project created
- GKE API enabled in your project

### 2. Software Installed

**gcloud CLI** (Google Cloud command-line tool):
```bash
# On macOS:
brew install google-cloud-sdk

# Or download from: https://cloud.google.com/sdk/docs/install
```

**kubectl** (Kubernetes command-line tool):
```bash
# Usually comes with gcloud, or install separately:
brew install kubectl
```

**gke-gcloud-auth-plugin** (Required for kubectl to authenticate):
```bash
gcloud components install gke-gcloud-auth-plugin

# Or on macOS:
brew install google-cloud-sdk-gke-gcloud-auth-plugin
```

### 3. DeathStarBench Source Code
- The DeathStarBench source code should be in: `../socialNetwork/` (relative to this project)

---

## Understanding the Architecture

### What You're Deploying

DeathStarBench Social Network is a **microservices application** with these components:

#### 1. **11 Microservices** (the actual application logic)
- `user-service` - User account management
- `social-graph-service` - Friend connections
- `compose-post-service` - Creating posts
- `post-storage-service` - Storing posts
- `home-timeline-service` - Home page feed
- `user-timeline-service` - User's personal feed
- `media-service` - Image/video handling
- `url-shorten-service` - Shortening URLs
- `text-service` - Text processing
- `unique-id-service` - Generating unique IDs
- `user-mention-service` - @mentions in posts

#### 2. **6 MongoDB Databases** (data storage)
- One database per service that needs storage
- Stores user data, posts, relationships, etc.

#### 3. **7 Cache Services** (fast data access)
- **3 Redis** instances - For timeline caching
- **4 Memcached** instances - For other caching

#### 4. **nginx-thrift Gateway** (API gateway)
- Receives HTTP requests from users
- Routes requests to the appropriate microservice
- Acts as the entry point to your application

#### 5. **Jaeger** (monitoring)
- Distributed tracing system
- Helps debug issues across services

**Total: ~28 pods** when everything is running

---

## Cluster Setup

### Create GKE Cluster

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Create cluster (this takes 5-10 minutes)
gcloud container clusters create social-network-cluster \
  --zone us-central1-a \
  --num-nodes 3 \
  --machine-type e2-medium \
  --enable-autoscaling \
  --min-nodes 2 \
  --max-nodes 5

# Connect kubectl to your cluster
gcloud container clusters get-credentials social-network-cluster \
  --zone us-central1-a
```

**What this does:**
- Creates a Kubernetes cluster with 3 nodes
- Each node is `e2-medium` (2 vCPU, 4GB RAM)
- Enables autoscaling (2-5 nodes)
- Connects your kubectl to the cluster

### Why 3 Nodes?

With all pods running, you need:
- **Total CPU requests**: ~2500-3000m (2.5-3 cores)
- **Each e2-medium node**: 1930m CPU available
- **3 nodes**: ~5790m total (enough with headroom)

You can start with 2 nodes, but you may experience CPU constraints.

---

## Deployment Steps

### Quick Deploy (Automated)

Just run the deployment script:

```bash
cd /path/to/deathstarbench-socialnetwork/project
chmod +x deploy-everything.sh
./deploy-everything.sh
```

This script does everything automatically. It takes about 5-10 minutes.

### Manual Deploy (Step by Step)

If you prefer to understand each step:

#### Step 1: Create ConfigMaps

ConfigMaps store configuration files that pods need:

```bash
cd /path/to/deathstarbench-socialnetwork/project

# Create main config
kubectl create configmap deathstarbench-config \
  --from-file=service-config.json=../socialNetwork/config/service-config.json \
  --from-file=jaeger-config.yml=../socialNetwork/config/jaeger-config.yml \
  --from-file=nginx.conf=../socialNetwork/nginx-web-server/conf/nginx.conf \
  --from-file=jaeger-config.json=../socialNetwork/nginx-web-server/jaeger-config.json

# Create pages (HTML/JS/CSS)
kubectl create configmap nginx-pages \
  --from-file=../socialNetwork/nginx-web-server/pages/

# Create generated Lua files
kubectl create configmap nginx-gen-lua \
  --from-file=../socialNetwork/gen-lua/
```

**Why ConfigMaps?**
- Pods need configuration files (nginx.conf, service-config.json, etc.)
- ConfigMaps let us store these files in Kubernetes
- Pods mount ConfigMaps as volumes (like attaching a USB drive)

#### Step 2: Deploy Databases First

Databases must start before services that use them:

```bash
# Deploy all MongoDB databases
for db in media-mongodb post-storage-mongodb social-graph-mongodb \
          url-shorten-mongodb user-mongodb user-timeline-mongodb; do
  kubectl apply -f kubernetes/deployments/databases/${db}-deployment.yaml
done

# Wait for databases to be ready (MongoDB takes time to start)
sleep 30
```

**Why deploy databases first?**
- Services connect to databases on startup
- If databases aren't ready, services will fail to start

#### Step 3: Deploy Cache Services

```bash
# Deploy Redis and Memcached
for cache in home-timeline-redis social-graph-redis user-timeline-redis \
            media-memcached post-storage-memcached url-shorten-memcached \
            user-memcached; do
  kubectl apply -f kubernetes/deployments/caches/${cache}-deployment.yaml
done

sleep 20
```

#### Step 4: Deploy Microservices

```bash
# Deploy all 11 services
for service in compose-post-service home-timeline-service media-service \
              post-storage-service social-graph-service text-service \
              unique-id-service url-shorten-service user-mention-service \
              user-timeline-service user-service; do
  kubectl apply -f kubernetes/deployments/${service}-deployment.yaml
done

sleep 30
```

#### Step 5: Deploy Supporting Services

```bash
# Deploy Jaeger (tracing)
kubectl apply -f kubernetes/deployments/jaeger-deployment.yaml

# Deploy nginx-thrift gateway
kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml

sleep 30
```

#### Step 6: Create Services (Networking)

Kubernetes Services create network endpoints:

```bash
# Deploy all Service objects
for service_file in kubernetes/services/*.yaml; do
  kubectl apply -f "$service_file"
done
```

**What are Services?**
- Pods have IP addresses that change when they restart
- Services create stable network endpoints (like a phone number)
- Other services use Service names to connect (e.g., `user-mongodb-service`)

---

## Memory & Resource Requirements

### Per-Pod Resources

#### Microservices (11 pods)
- **CPU request**: 100m (0.1 cores) each = **1100m total**
- **CPU limit**: 1000m (1 core) each
- **Memory request**: 128Mi each = **~1.4GB total**
- **Memory limit**: 512Mi each

#### MongoDB (6 pods)
- **CPU request**: 100m each = **600m total**
- **CPU limit**: 1000m each
- **Memory request**: 512Mi each = **~3GB total**
- **Memory limit**: 2Gi each

#### Redis/Memcached (7 pods)
- **CPU request**: 50-100m each = **~500m total**
- **Memory request**: 64-128Mi each = **~500MB total**

#### nginx-thrift (1 pod)
- **CPU request**: 50m
- **CPU limit**: 1000m
- **Memory request**: 128Mi
- **Memory limit**: 512Mi

#### Jaeger (1 pod)
- **CPU request**: 100m
- **Memory request**: 256Mi

### Total Requirements

**Minimum:**
- **CPU**: ~2500m (2.5 cores) requested
- **Memory**: ~5-6GB requested
- **Nodes**: 3x e2-medium (each has 1930m CPU, 3.75GB RAM)

**Recommended:**
- **3-4 nodes** of e2-medium for comfortable operation
- Allows room for scaling and avoids resource constraints

### Resource Limits vs Requests

- **Request**: Guaranteed minimum resources
- **Limit**: Maximum resources a pod can use
- Kubernetes uses requests to decide which node to place a pod on
- Limits prevent pods from using too much

---
## Verification Script

You can verify with this quick test:

```bash
# 1. Clean everything
./cleanup-everything.sh

# 2. Wait a moment
sleep 5

# 3. Deploy everything
./deploy-everything.sh

# 4. Check counts (after deployment completes)
echo "=== Resource Counts ==="
echo "Deployments: $(kubectl get deployments --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "Services: $(kubectl get svc --no-headers 2>/dev/null | grep -v kubernetes | wc -l | tr -d ' ')"
echo "ConfigMaps: $(kubectl get configmap --no-headers 2>/dev/null | grep -v kube-root-ca.crt | wc -l | tr -d ' ')"
echo "PVCs: $(kubectl get pvc --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "Pods: $(kubectl get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')"
```

## Common Issues & Fixes

### Issue 1: Pods Stuck in "Pending"

**Cause**: Not enough CPU/memory on nodes

**Check:**
```bash
kubectl describe node | grep -A 5 "Allocated resources"
```

**Fix:**
- Scale cluster: `gcloud container clusters resize social-network-cluster --num-nodes 4 --zone us-central1-a`
- Or reduce resource requests in deployment files

### Issue 2: Pods in "CrashLoopBackOff"

**Cause**: Application error, missing config, or connection issues

**Check logs:**
```bash
kubectl logs <pod-name>
kubectl logs <pod-name> --previous  # Logs from crashed container
```

**Common causes:**
- Missing ConfigMaps
- Database not ready
- Incorrect configuration

### Issue 3: Duplicate Pods

**Cause**: Old ReplicaSets from previous deployments

**Fix:**
```bash
# Scale deployment to correct number
kubectl scale deployment <deployment-name> --replicas=1

# Delete old ReplicaSets
kubectl get rs
kubectl delete rs <old-replicaset-name>
```

### Issue 4: MongoDB Corruption

**Cause**: Database files corrupted (usually from improper shutdown)

**Fix:**
```bash
# Scale down
kubectl scale deployment <mongodb-deployment> --replicas=0

# Delete PVC
kubectl delete pvc <mongodb-pvc-name>

# Scale back up (creates new PVC)
kubectl scale deployment <mongodb-deployment> --replicas=1
```

**Note**: This deletes all data! OK for testing, not for production.

### Issue 5: nginx-thrift Health Checks Failing

**Cause**: nginx takes time to start, health checks fail too quickly

**Fix**: Health checks are disabled in the deployment YAML. If you re-enable them, increase `initialDelaySeconds` to 60+ seconds.

---

## Testing Your Deployment

### 1. Check All Pods Are Running

```bash
kubectl get pods
```

You should see:
- 11 service pods (all Running)
- 6 MongoDB pods (all Running)
- 7 cache pods (all Running)
- 1 nginx-thrift pod (Running)
- 1 Jaeger pod (Running)

**Total: 26 pods**

### 2. Get nginx-thrift Service

```bash
kubectl get svc nginx-thrift-service
```

This shows the service endpoint.

### 3. Port-Forward to Test

```bash
# Forward port 8080 from your computer to the service
kubectl port-forward svc/nginx-thrift-service 8080:8080
```

**What this does:**
- Creates a tunnel from `localhost:8080` to the service
- You can test the API from your computer
- Press Ctrl+C to stop

### 4. Test the API

In another terminal:

```bash
# Test if nginx is responding
curl http://localhost:8080/

# Or open in browser
open http://localhost:8080/
```

### 5. Run k6 Load Tests

```bash
# Make sure port-forward is running in another terminal

# Run the load test
k6 run k6-tests/constant-load.js
```

---

## Troubleshooting Commands

```bash
# View all pods
kubectl get pods

# View pods with more details
kubectl get pods -o wide

# View pod logs
kubectl logs <pod-name>

# View pod events (why it's failing)
kubectl describe pod <pod-name>

# View all services
kubectl get svc

# View ConfigMaps
kubectl get configmaps

# View node resources
kubectl describe nodes | grep -A 10 "Allocated resources"

# Restart a deployment
kubectl rollout restart deployment/<deployment-name>

# View deployment status
kubectl get deployments
```

---

## Clean Up

To delete everything:

```bash
# Delete all deployments
kubectl delete deployment --all

# Delete all services
kubectl delete svc --all

# Delete all ConfigMaps
kubectl delete configmap --all

# Delete all PVCs (persistent storage)
kubectl delete pvc --all

# Delete the cluster (optional)
gcloud container clusters delete social-network-cluster --zone us-central1-a
```

---

## Next Steps

1. **Set up autoscaling** - Configure HPA (Horizontal Pod Autoscaler)
2. **Fix nginx-lua-scripts** - Add Lua scripts ConfigMap properly
3. **Set up monitoring** - Configure Prometheus & Grafana
4. **Production hardening** - Security, backups, etc.

---

## Summary

This deployment includes:
- ✅ 26 pods total
- ✅ All services communicating via Services
- ✅ Persistent storage for databases
- ✅ ConfigMaps for configuration
- ✅ Health checks (disabled for nginx initially)

The deployment script handles all of this automatically. Just run it and wait!

---

**Questions?** Check the troubleshooting section or look at pod logs for specific errors.

