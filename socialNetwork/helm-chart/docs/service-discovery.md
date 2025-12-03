# Service Discovery in Social Network Application

## Overview

The Social Network application uses **Kubernetes native service discovery** to enable microservices to find and communicate with each other.

## How It Works

### 1. Kubernetes Services

Each microservice has a corresponding Kubernetes Service that provides:
- **Stable DNS name**: `{service-name}.{namespace}.svc.cluster.local`
- **Load balancing**: Distributes traffic across all pod replicas
- **Service abstraction**: Pods can be replaced without changing service endpoints

### 2. Service Discovery Mechanism

```
┌─────────────────────────────────────────────────────────────┐
│  Client Pod (nginx-thrift)                                  │
│                                                              │
│  DNS Query: compose-post-service.cse239fall2025.svc...      │
│                    ↓                                         │
│  Kubernetes DNS (CoreDNS)                                    │
│                    ↓                                         │
│  Service: compose-post-service                               │
│                    ↓                                         │
│  Load Balancer distributes to:                               │
│  - compose-post-service-pod-1                                │
│  - compose-post-service-pod-2                                │
│  - compose-post-service-pod-3                                │
└─────────────────────────────────────────────────────────────┘
```

## Service Configuration

### Service Template

All services are created using the Helm template at:
`socialnetwork/templates/_baseService.tpl`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.name }}
  labels:
    service: {{ .Values.name }}
spec:
  type: ClusterIP  # Internal service discovery
  selector:
    service: {{ .Values.name }}
  ports:
  - port: 9090
    targetPort: 9090
```

### Service Types

| Service Type | Purpose | Example |
|--------------|---------|---------|
| **ClusterIP** | Internal service discovery (default) | All microservices |
| **NodePort** | External access via node IP | nginx-thrift (if needed) |
| **LoadBalancer** | Cloud provider load balancer | Production deployments |

## Service Discovery Examples

### Example 1: nginx-thrift → compose-post-service

**In nginx-thrift configuration:**
```lua
local compose_post_service = "compose-post-service.cse239fall2025.svc.cluster.local"
local res = httpc:request_uri("http://" .. compose_post_service .. ":9090/...")
```

**Service automatically:**
- Resolves DNS to service IP
- Load balances across all compose-post-service pods
- Handles pod failures gracefully

### Example 2: Service-to-Service Communication

**home-timeline-service → post-storage-service:**
```python
# Service discovery via DNS
post_storage_url = "http://post-storage-service.cse239fall2025.svc.cluster.local:9090"
response = requests.get(f"{post_storage_url}/posts/{post_id}")
```

## Service Discovery Features

### ✅ Automatic Load Balancing

When multiple pods exist, Kubernetes automatically distributes requests:

```bash
# 3 replicas of compose-post-service
kubectl get pods -n cse239fall2025 | grep compose-post-service

# Service automatically load balances across all 3
curl http://compose-post-service.cse239fall2025.svc.cluster.local:9090
```

### ✅ Health Checks

Services only route to healthy pods:

```yaml
# Pod health checks (in deployment)
livenessProbe:
  httpGet:
    path: /health
    port: 9090
  initialDelaySeconds: 30
  periodSeconds: 10
```

### ✅ DNS Resolution

All services are discoverable via DNS:

```bash
# From within cluster
nslookup compose-post-service.cse239fall2025.svc.cluster.local

# Short form (same namespace)
nslookup compose-post-service
```

## Service Discovery in Action

### List All Services

```bash
kubectl get svc -n cse239fall2025
```

**Output:**
```
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
compose-post-service      ClusterIP   10.96.1.10     <none>        9090/TCP
home-timeline-service     ClusterIP   10.96.1.11     <none>        9090/TCP
nginx-thrift              ClusterIP   10.96.1.12     <none>        8080/TCP
...
```

### Test Service Discovery

```bash
# From inside a pod
kubectl run -it --rm debug --image=busybox --restart=Never -n cse239fall2025 -- sh

# Inside the debug pod:
nslookup compose-post-service
# Returns: 10.96.1.10

wget -O- http://compose-post-service:9090/health
```

## Service Discovery Benefits

1. **Decoupling**: Services don't need to know pod IPs
2. **Scalability**: Add/remove pods without reconfiguration
3. **Reliability**: Automatic failover to healthy pods
4. **Simplicity**: DNS-based, no external service registry needed

## Integration with HPA

When HPA scales pods, service discovery automatically includes new pods:

```bash
# HPA scales compose-post-service from 1 → 3 pods
kubectl get hpa compose-post-service-hpa -n cse239fall2025

# Service automatically discovers and load balances to all 3 pods
kubectl get endpoints compose-post-service -n cse239fall2025
```

## Monitoring Service Discovery

### Check Service Endpoints

```bash
kubectl get endpoints -n cse239fall2025
```

Shows which pods each service routes to.

### Service Discovery Metrics

Monitor in Grafana:
- Service endpoint count (should match pod replicas)
- DNS resolution latency
- Service-to-service request latency

## Troubleshooting

### Service Not Resolving

```bash
# Check service exists
kubectl get svc compose-post-service -n cse239fall2025

# Check DNS
kubectl run -it --rm debug --image=busybox --restart=Never -n cse239fall2025 -- nslookup compose-post-service
```

### No Endpoints

```bash
# Service has no pods to route to
kubectl get endpoints compose-post-service -n cse239fall2025

# Check pod labels match service selector
kubectl get pods -l service=compose-post-service -n cse239fall2025
```

## Summary

✅ **Service Discovery**: Kubernetes Services provide DNS-based discovery  
✅ **Load Balancing**: Automatic across all pod replicas  
✅ **Health Checks**: Only routes to healthy pods  
✅ **Scalability**: Works seamlessly with HPA  
✅ **Zero Configuration**: No external service registry needed

