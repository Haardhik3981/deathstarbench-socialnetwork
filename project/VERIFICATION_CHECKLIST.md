# Deployment Verification Checklist

## What Cleanup Script Deletes ✅

1. All Deployments (26 total)
2. All Services (Kubernetes Service objects)
3. All ConfigMaps (3)
4. All PVCs (6)
5. Orphaned Pods/ReplicaSets

## What Deploy Script Creates ✅

### Deployments (26 total)

**Databases (6) - Each creates a PVC automatically:**
1. ✅ media-mongodb-deployment → Creates media-mongodb-pvc
2. ✅ post-storage-mongodb-deployment → Creates post-storage-mongodb-pvc
3. ✅ social-graph-mongodb-deployment → Creates social-graph-mongodb-pvc
4. ✅ url-shorten-mongodb-deployment → Creates url-shorten-mongodb-pvc
5. ✅ user-mongodb-deployment → Creates user-mongodb-pvc
6. ✅ user-timeline-mongodb-deployment → Creates user-timeline-mongodb-pvc

**Cache Services (7):**
7. ✅ social-graph-redis-deployment (from redis-deployments.yaml)
8. ✅ home-timeline-redis-deployment (from redis-deployments.yaml)
9. ✅ user-timeline-redis-deployment (from redis-deployments.yaml)
10. ✅ user-memcached-deployment (from memcached-deployments.yaml)
11. ✅ post-storage-memcached-deployment (from memcached-deployments.yaml)
12. ✅ url-shorten-memcached-deployment (from memcached-deployments.yaml)
13. ✅ media-memcached-deployment (from memcached-deployments.yaml)

**Microservices (11):**
14. ✅ compose-post-service-deployment
15. ✅ home-timeline-service-deployment
16. ✅ media-service-deployment
17. ✅ post-storage-service-deployment
18. ✅ social-graph-service-deployment
19. ✅ text-service-deployment
20. ✅ unique-id-service-deployment
21. ✅ url-shorten-service-deployment
22. ✅ user-mention-service-deployment
23. ✅ user-timeline-service-deployment
24. ✅ user-service-deployment

**Supporting Services (2):**
25. ✅ jaeger-deployment (includes Service inline)
26. ✅ nginx-thrift-deployment

### ConfigMaps (3)

1. ✅ deathstarbench-config (service-config.json, nginx.conf, jaeger-config files)
2. ✅ nginx-pages (HTML/JS/CSS)
3. ✅ nginx-gen-lua (Generated Lua files)

**Note:** nginx-lua-scripts intentionally skipped

### PVCs (6 - Auto-created)

Created automatically when MongoDB deployments are applied:
1. ✅ media-mongodb-pvc
2. ✅ post-storage-mongodb-pvc
3. ✅ social-graph-mongodb-pvc
4. ✅ url-shorten-mongodb-pvc
5. ✅ user-mongodb-pvc
6. ✅ user-timeline-mongodb-pvc

### Services (Kubernetes Service objects)

Deployed from `kubernetes/services/*.yaml`:
- ✅ all-databases.yaml (multiple services)
- ✅ all-microservices.yaml (multiple services)
- ✅ nginx-service.yaml (nginx-thrift service)
- ✅ Plus jaeger service (inline in jaeger-deployment.yaml)

## ✅ VERIFICATION: Deploy Creates Everything Cleanup Deletes!

**Match Status:** ✅ PERFECT MATCH

The deploy script creates:
- ✅ All 26 deployments
- ✅ All Services
- ✅ All 3 ConfigMaps
- ✅ All 6 PVCs (auto-created)

The only exception is `nginx-lua-scripts` ConfigMap which is intentionally skipped and documented.

