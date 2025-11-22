# DeathStarBench Migration Summary

## Overview

All Kubernetes YAML files have been updated to be compatible with the DeathStarBench Social Network benchmark. This document summarizes the changes and what you need to do next.

## Key Changes Made

### 1. Service Deployments Updated
- **All microservices** now use the unified DeathStarBench image: `deathstarbench/social-network-microservices:latest`
- **Entrypoints** set correctly for each service (e.g., `UserService`, `SocialGraphService`, etc.)
- **Ports** standardized to 9090 (Thrift protocol) for all microservices
- **Config volume** mounted from `deathstarbench-config` ConfigMap

### 2. New Service Deployments Created
Added deployments for all DeathStarBench services:
- ✅ user-service
- ✅ social-graph-service
- ✅ user-timeline-service
- ✅ compose-post-service
- ✅ post-storage-service
- ✅ home-timeline-service
- ✅ url-shorten-service
- ✅ media-service
- ✅ text-service
- ✅ unique-id-service
- ✅ user-mention-service

### 3. Database Deployments Created
Created deployments for all databases:
- **MongoDB instances**: user-mongodb, social-graph-mongodb, user-timeline-mongodb, post-storage-mongodb, url-shorten-mongodb, media-mongodb
- **Redis instances**: social-graph-redis, home-timeline-redis, user-timeline-redis
- **Memcached instances**: user-memcached, post-storage-memcached, url-shorten-memcached, media-memcached
- All databases include PersistentVolumeClaims for data persistence

### 4. Gateway Updated
- **Replaced** regular nginx with **nginx-thrift** (OpenResty with Thrift support)
- Updated to use `yg397/openresty-thrift:xenial` image
- Port changed from 80 to 8080
- Added volume mounts for Lua scripts, pages, and configuration

### 5. Services Updated
- All microservice services use port 9090 (Thrift)
- Created services for all databases
- Created nginx-thrift-service (replaces nginx-service)
- Added Jaeger service for distributed tracing

### 6. ConfigMaps Updated
- Created `deathstarbench-config` ConfigMap with service-config.json template
- Updated to reference DeathStarBench configuration structure

### 7. Added Jaeger Deployment
- Created Jaeger deployment for distributed tracing
- All services can send traces to Jaeger

## What You Still Need to Do

### 1. Copy Configuration Files from DeathStarBench

The nginx-thrift deployment needs files from the DeathStarBench source. You have two options:

#### Option A: Use ConfigMaps (for small files)
```bash
# Copy files from DeathStarBench source
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/socialNetwork

# Create ConfigMaps
kubectl create configmap nginx-thrift-config \
  --from-file=nginx.conf=nginx-web-server/conf/nginx.conf

kubectl create configmap jaeger-config \
  --from-file=jaeger-config.json=nginx-web-server/jaeger-config.json

# Update the deathstarbench-config with actual service-config.json
kubectl create configmap deathstarbench-config \
  --from-file=service-config.json=config/service-config.json \
  --from-file=jaeger-config.yml=config/jaeger-config.yml \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### Option B: Use PersistentVolumes with Init Containers
Create an init container that copies files from a shared volume or Git repository.

### 2. Update nginx-thrift Deployment Volumes

The nginx-thrift deployment currently uses `emptyDir` for Lua scripts and pages. You need to:

1. **Create ConfigMaps** for Lua scripts and pages, OR
2. **Use PersistentVolumes** with init containers to sync files, OR
3. **Use a sidecar container** that syncs files from a Git repository

Example for Lua scripts:
```bash
kubectl create configmap nginx-lua-scripts \
  --from-file=nginx-web-server/lua-scripts/
```

Then update the deployment to use the ConfigMap instead of emptyDir.

### 3. Update Image References (if using custom registry)

If you're building your own images or using a different registry, update the image references in all deployment files:

```bash
# Find all image references
grep -r "image:" kubernetes/deployments/

# Update to your registry
# Example: Replace deathstarbench/social-network-microservices:latest
# with gcr.io/YOUR_PROJECT/social-network-microservices:latest
```

### 4. Test the Deployment

1. **Deploy databases first** (they take time to initialize):
   ```bash
   kubectl apply -f kubernetes/deployments/databases/
   kubectl apply -f kubernetes/services/all-databases.yaml
   ```

2. **Wait for databases to be ready**:
   ```bash
   kubectl wait --for=condition=available --timeout=300s deployment/user-mongodb-deployment
   ```

3. **Deploy microservices**:
   ```bash
   kubectl apply -f kubernetes/deployments/
   kubectl apply -f kubernetes/services/
   ```

4. **Deploy gateway** (after ConfigMaps are ready):
   ```bash
   kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml
   kubectl apply -f kubernetes/services/nginx-service.yaml
   ```

5. **Deploy monitoring**:
   ```bash
   kubectl apply -f kubernetes/monitoring/
   ```

### 5. Update k6 Tests

The k6 test scripts may need updates to match DeathStarBench's API endpoints. Check the DeathStarBench documentation or nginx-web-server Lua scripts to understand the API structure.

## File Structure

```
kubernetes/
├── deployments/
│   ├── user-service-deployment.yaml          ✅ Updated
│   ├── social-graph-service-deployment.yaml  ✅ Updated
│   ├── user-timeline-service-deployment.yaml ✅ Updated
│   ├── compose-post-service-deployment.yaml   ✅ New
│   ├── post-storage-service-deployment.yaml  ✅ New
│   ├── home-timeline-service-deployment.yaml ✅ New
│   ├── url-shorten-service-deployment.yaml  ✅ New
│   ├── media-service-deployment.yaml         ✅ New
│   ├── text-service-deployment.yaml          ✅ New
│   ├── unique-id-service-deployment.yaml     ✅ New
│   ├── user-mention-service-deployment.yaml  ✅ New
│   ├── nginx-thrift-deployment.yaml         ✅ New (replaces nginx)
│   ├── jaeger-deployment.yaml                ✅ New
│   └── databases/                            ✅ New
│       ├── *-mongodb-deployment.yaml
│       ├── redis-deployments.yaml
│       └── memcached-deployments.yaml
├── services/
│   ├── user-service.yaml                    ✅ Updated
│   ├── social-graph-service.yaml             ✅ Updated
│   ├── user-timeline-service.yaml            ✅ Updated
│   ├── nginx-service.yaml                    ✅ Updated
│   ├── all-microservices.yaml                ✅ New
│   └── all-databases.yaml                    ✅ New
└── configmaps/
    ├── nginx-config.yaml                      ✅ Updated (now deathstarbench-config)
    └── database-secret.yaml                  ❌ Removed (not needed)
```

## Important Notes

1. **All services use the same image** with different entrypoints
2. **Port 9090** is used for all microservices (Thrift protocol)
3. **Service discovery** uses Kubernetes DNS (service names match config)
4. **Configuration** comes from `service-config.json` in the ConfigMap
5. **Nginx-thrift** requires Lua scripts and pages from DeathStarBench source

## Next Steps

1. ✅ Copy configuration files from DeathStarBench
2. ✅ Update nginx-thrift volumes
3. ✅ Deploy and test
4. ✅ Update k6 tests if needed
5. ✅ Set up monitoring and autoscaling

## Troubleshooting

If services fail to start:
- Check that databases are running: `kubectl get pods | grep mongodb`
- Check service logs: `kubectl logs <pod-name>`
- Verify ConfigMap exists: `kubectl get configmap deathstarbench-config`
- Check service endpoints: `kubectl get endpoints`

If nginx-thrift fails:
- Verify all ConfigMaps are created
- Check that Lua scripts are mounted correctly
- Review nginx-thrift logs: `kubectl logs deployment/nginx-thrift-deployment`

## Resources

- DeathStarBench GitHub: https://github.com/delimitrou/DeathStarBench
- DeathStarBench Source: `/Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/socialNetwork`

