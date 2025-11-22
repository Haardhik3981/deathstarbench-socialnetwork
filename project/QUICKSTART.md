# Quick Start Guide

This is a quick reference guide to get you started. For detailed information, see the [README.md](README.md) and [deployment guide](docs/deployment-guide.md).

## What You've Built

You now have a complete microservice deployment setup with:

1. **Dockerfiles** - Container images for each microservice
2. **Kubernetes Manifests** - Deployments, Services, ConfigMaps, Secrets
3. **Autoscaling** - HPA and VPA configurations
4. **Monitoring** - Prometheus and Grafana setup
5. **Load Testing** - k6 test scripts for different scenarios
6. **Deployment Scripts** - Automated deployment to GKE and Nautilus

## File Structure Overview

```
project/
├── docker/                   # Dockerfiles for each service
│   ├── nginx/                # Reverse proxy
│   ├── user/                 # User service
│   ├── social-graph/         # Social graph service
│   └── user-timeline/        # Timeline service
│
├── kubernetes/               # Kubernetes manifests
│   ├── deployments/          # Pod deployment configs
│   ├── services/             # Service definitions
│   ├── autoscaling/          # HPA and VPA configs
│   ├── monitoring/           # Prometheus & Grafana
│   └── configmaps/           # Configuration files
│
├── k6-tests/                 # Load testing scripts
│   ├── constant-load.js      # Steady load test
│   ├── peak-test.js          # Traffic spike test
│   ├── stress-test.js        # Gradual ramp-up test
│   └── endurance-test.js     # Long-duration test
│
└── scripts/                  # Deployment automation
    ├── deploy-gke.sh         # Deploy to Google Cloud
    ├── deploy-nautilus.sh    # Deploy to Nautilus
    ├── setup-monitoring.sh   # Set up monitoring
    └── run-k6-tests.sh       # Run load tests
```

## Key Concepts Explained

### Dockerfiles
- **What**: Instructions for building container images
- **Why**: Package applications with all dependencies
- **Where**: `docker/` directory

### Kubernetes Deployments
- **What**: Define how many pods to run and what containers they contain
- **Why**: Manage application lifecycle, scaling, updates
- **Where**: `kubernetes/deployments/`

### Kubernetes Services
- **What**: Stable network endpoints for pods
- **Why**: Pods have changing IPs; services provide stable addresses
- **Where**: `kubernetes/services/`

### HPA (Horizontal Pod Autoscaler)
- **What**: Automatically scales number of pods based on metrics
- **Why**: Handle varying load without manual intervention
- **Where**: `kubernetes/autoscaling/`

### VPA (Vertical Pod Autoscaler)
- **What**: Automatically adjusts CPU/memory per pod
- **Why**: Optimize resource usage based on actual needs
- **Where**: `kubernetes/autoscaling/`

### Prometheus
- **What**: Time-series database for metrics
- **Why**: Collect and store performance metrics
- **Where**: `kubernetes/monitoring/`

### Grafana
- **What**: Visualization tool for metrics
- **Why**: Create dashboards to understand system behavior
- **Where**: `kubernetes/monitoring/`

### k6 Tests
- **What**: Load testing scripts
- **Why**: Validate system performance under load
- **Where**: `k6-tests/`

## Next Steps

1. **Get DeathStarBench Source Code**
   ```bash
   git clone https://github.com/delimitrou/DeathStarBench.git
   ```

2. **Build Docker Images**
   - Adapt the Dockerfiles to match DeathStarBench's actual structure
   - Build and push images to your container registry

3. **Update Image References**
   - Edit deployment YAML files to use your image URLs

4. **Deploy to Kubernetes**
   ```bash
   # For GKE
   ./scripts/deploy-gke.sh
   
   # For Nautilus
   ./scripts/deploy-nautilus.sh
   ```

5. **Set Up Monitoring**
   ```bash
   ./scripts/setup-monitoring.sh
   ```

6. **Run Load Tests**
   ```bash
   export BASE_URL="http://your-service-url"
   ./scripts/run-k6-tests.sh constant-load
   ```

## Learning Resources

- **Kubernetes Basics**: https://kubernetes.io/docs/tutorials/
- **Docker Basics**: https://docs.docker.com/get-started/
- **Prometheus**: https://prometheus.io/docs/introduction/overview/
- **k6**: https://k6.io/docs/

## Common Commands

```bash
# Check pod status
kubectl get pods

# View pod logs
kubectl logs <pod-name>

# Check services
kubectl get services

# Check HPA status
kubectl get hpa

# Port forward to access services
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Scale a deployment manually
kubectl scale deployment/user-service-deployment --replicas=5

# Delete everything
kubectl delete -f kubernetes/
```

## Getting Help

- Check the detailed comments in each file
- Review the [deployment guide](docs/deployment-guide.md)
- Check Kubernetes documentation
- Look at error messages and logs

Good luck with your project! 🚀

