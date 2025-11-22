# Deployment Guide

## Overview

This guide walks you through deploying the DeathStarBench Social Network application to Kubernetes, setting up monitoring, and running load tests.

## Prerequisites

### Local Development
- Docker Desktop installed and running
- kubectl CLI installed
- k6 installed (for load testing)

### For GKE Deployment
- Google Cloud SDK (gcloud) installed
- GCP project with billing enabled
- GKE cluster created
- Appropriate IAM permissions

### For Nautilus Deployment
- Access to Nautilus cluster
- kubectl configured for Nautilus
- Appropriate namespace and quotas

## Step-by-Step Deployment

### 1. Clone DeathStarBench

First, you need to get the DeathStarBench source code:

```bash
cd /path/to/your/workspace
git clone https://github.com/delimitrou/DeathStarBench.git
cd DeathStarBench/socialNetwork
```

### 2. Build Docker Images

#### For GKE (Google Container Registry)

```bash
# Set your GCP project ID
export GCP_PROJECT_ID="your-project-id"
export REGISTRY="gcr.io/${GCP_PROJECT_ID}"

# Build and push images
docker build -t ${REGISTRY}/user-service:latest ./services/user
docker push ${REGISTRY}/user-service:latest

# Repeat for other services...
```

#### For Nautilus (Docker Hub)

```bash
# Set your Docker Hub username
export DOCKER_USERNAME="your-username"
export REGISTRY="docker.io/${DOCKER_USERNAME}"

# Build and push images
docker build -t ${REGISTRY}/user-service:latest ./services/user
docker push ${REGISTRY}/user-service:latest
```

### 3. Update Kubernetes Manifests

Update the image references in the deployment YAML files:

```bash
# Edit kubernetes/deployments/user-service-deployment.yaml
# Change: image: user-service:latest
# To: image: gcr.io/YOUR_PROJECT/user-service:latest
# Or: image: docker.io/YOUR_USERNAME/user-service:latest
```

### 4. Deploy to Kubernetes

#### GKE Deployment

```bash
cd project/scripts
./deploy-gke.sh
```

This script will:
- Authenticate with GCP
- Create namespaces
- Deploy ConfigMaps and Secrets
- Build and push Docker images
- Deploy all services
- Set up monitoring
- Show service endpoints

#### Nautilus Deployment

```bash
cd project/scripts
./deploy-nautilus.sh
```

This script will:
- Convert LoadBalancer services to NodePort
- Deploy all services
- Set up monitoring
- Show NodePort endpoints

### 5. Verify Deployment

Check that all pods are running:

```bash
kubectl get pods
kubectl get services
kubectl get hpa
```

### 6. Access the Application

#### GKE
- Application: Use the LoadBalancer IP shown by the deployment script
- Grafana: Use the LoadBalancer IP on port 3000
- Prometheus: `kubectl port-forward -n monitoring svc/prometheus 9090:9090`

#### Nautilus
- Application: `http://<node-ip>:<nodeport>`
- Find node IP: `kubectl get nodes -o wide`
- Find NodePort: `kubectl get service nginx-service`

### 7. Set Up Monitoring

If monitoring wasn't deployed automatically:

```bash
cd project/scripts
./setup-monitoring.sh
```

### 8. Run Load Tests

```bash
# Set the base URL
export BASE_URL="http://<your-service-url>"

# Run a specific test
cd project/scripts
./run-k6-tests.sh constant-load
./run-k6-tests.sh peak-test
./run-k6-tests.sh stress-test

# Or run all tests
./run-k6-tests.sh all
```

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

### Services Not Accessible

```bash
# Check service endpoints
kubectl get endpoints

# Test service from within cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- wget -O- http://user-service:8080/health
```

### HPA Not Scaling

```bash
# Check HPA status
kubectl describe hpa user-service-hpa

# Check if metrics-server is running
kubectl get deployment metrics-server -n kube-system

# For custom metrics, check Prometheus Adapter
kubectl get apiservice | grep metrics
```

### Prometheus Not Scraping

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check Prometheus logs
kubectl logs -n monitoring deployment/prometheus
```

## Next Steps

1. **Customize HPA/VPA**: Adjust thresholds based on your workload
2. **Create Grafana Dashboards**: Visualize key metrics
3. **Set Up Alerts**: Configure alerting rules in Prometheus
4. **Optimize Resources**: Use VPA recommendations to optimize resource requests
5. **Cost Analysis**: Monitor GCP costs and optimize resource usage

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [k6 Documentation](https://k6.io/docs/)
- [DeathStarBench GitHub](https://github.com/delimitrou/DeathStarBench)

