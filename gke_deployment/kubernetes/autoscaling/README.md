# Autoscaling Configuration

HPA (Horizontal Pod Autoscaler) and VPA (Vertical Pod Autoscaler) configurations for performance/cost optimization.

## Directory Structure

```
autoscaling/
├── README.md                    # This file
├── hpa/                         # Horizontal Pod Autoscaler configs
│   ├── user-service-hpa.yaml
│   ├── compose-post-service-hpa.yaml
│   ├── home-timeline-service-hpa.yaml
│   └── ... (12 HPA configs total)
├── vpa/                         # Vertical Pod Autoscaler configs
│   ├── user-service-vpa.yaml
│   ├── compose-post-service-vpa.yaml
│   ├── home-timeline-service-vpa.yaml
│   └── ... (12 VPA configs total)
├── user-service-vpa-experiments.yaml  # Multiple VPA configurations for experiments
├── prometheus-adapter-config.yaml    # Prometheus Adapter for custom metrics
└── HPA_DETAILED_EXPLANATION.md       # Detailed HPA documentation
```

## HPA Configurations

### Location: `hpa/`

| File | Service | Metrics | Target |
|------|---------|---------|--------|
| `user-service-hpa.yaml` | User Service | CPU 70%, Memory 80% | 1-10 replicas |
| `compose-post-service-hpa.yaml` | Compose Post | CPU 70%, Memory 80% | 1-10 replicas |
| `home-timeline-service-hpa.yaml` | Home Timeline | CPU 70%, Memory 80% | 1-10 replicas |
| `nginx-thrift-hpa.yaml` | Nginx Gateway | CPU 70%, Memory 80% | 1-10 replicas |
| ... | (8 more services) | CPU 70%, Memory 80% | 1-10 replicas |

**All HPAs:**
- Scale based on CPU (70% target) and Memory (80% target)
- Min replicas: 1
- Max replicas: 10 (social-graph: 8)
- Fast scale-up (0s stabilization)
- Conservative scale-down (60s stabilization)

## VPA Configurations

### Location: `vpa/`

| File | Service | Update Mode | CPU Range | Memory Range |
|------|---------|-------------|-----------|--------------|
| `user-service-vpa.yaml` | User Service | Off | 100m-2000m | 128Mi-1024Mi |
| `compose-post-service-vpa.yaml` | Compose Post | Off | 100m-1000m | 128Mi-512Mi |
| `home-timeline-service-vpa.yaml` | Home Timeline | Off | 100m-1000m | 128Mi-512Mi |
| ... | (9 more services) | Off | Varies | Varies |

**All VPAs:**
- Update mode: **Off** (recommendations only, no automatic updates)
- Provides resource recommendations based on historical usage
- View recommendations: `kubectl describe vpa <service-name>-vpa`

## Experiment Configurations

### `user-service-vpa-experiments.yaml`

Multiple VPA configurations for testing:
- **Conservative**: Lower cost per pod, more pods needed
- **Moderate**: Balanced cost and performance
- **Aggressive**: Higher cost per pod, fewer pods needed
- **CPU-Optimized**: High CPU, moderate memory
- **Memory-Optimized**: Moderate CPU, high memory

## Quick Start

### Apply All HPAs
```bash
kubectl apply -f kubernetes/autoscaling/hpa/
```

### Apply All VPAs
```bash
kubectl apply -f kubernetes/autoscaling/vpa/
```

### Check Status
```bash
# HPA status
kubectl get hpa -n default

# VPA recommendations
kubectl get vpa -n default

# Detailed VPA recommendations
kubectl describe vpa user-service-vpa -n default
```

## Monitoring

### Watch HPA Scaling
```bash
kubectl get hpa -w
```

### Watch VPA Recommendations
```bash
watch -n 5 'kubectl get vpa -n default'
```

### View Pod Resources
```bash
kubectl get pods -o custom-columns=NAME:.metadata.name,CPU-REQ:.spec.containers[0].resources.requests.cpu,MEM-REQ:.spec.containers[0].resources.requests.memory
```

## Configuration Details

### HPA Behavior
- **Scale-up**: Immediate (0s stabilization), up to 100% increase or 2 pods
- **Scale-down**: 60s stabilization, up to 50% decrease
- **Metrics**: CPU and memory utilization percentages

### VPA Behavior
- **Update Mode**: Off (recommendations only)
- **Learning Period**: 10-15 minutes of moderate load
- **Recommendations**: Based on historical usage patterns
- **To Apply**: Manually update deployment resource requests/limits

## Best Practices

1. **Start with HPA**: Apply HPAs first to enable horizontal scaling
2. **Monitor VPA**: Let VPA collect data for 15+ minutes before checking recommendations
3. **CPU-Based Scaling**: Use reduced CPU requests (100m) to force CPU-based scaling
4. **Test Gradually**: Start with low load, gradually increase
5. **Compare Configurations**: Test different VPA settings to find optimal cost/performance

## Troubleshooting

### HPA Not Scaling
```bash
# Check metrics availability
kubectl top pods

# Check HPA status
kubectl describe hpa user-service-hpa
```

### VPA No Recommendations
```bash
# Check VPA status
kubectl describe vpa user-service-vpa

# Ensure VPA has collected data (wait 15+ minutes)
```

## See Also

- `HPA_DETAILED_EXPLANATION.md` - Detailed HPA documentation
- `kubernetes/monitoring/METRICS_TRACKING_GUIDE.md` - Prometheus queries
- `../deployments/` - Deployment configurations
