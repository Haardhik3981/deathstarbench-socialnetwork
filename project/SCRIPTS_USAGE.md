# Scripts Usage Guide - Local vs GKE

## Overview

This guide explains how to use the deployment and testing scripts for both **local** (docker-compose) and **GKE** (Kubernetes) environments.

---

## Script: `run-k6-tests.sh`

### What It Does
Runs k6 load tests against your application. Works for both local and GKE environments.

### Usage

#### For Local Testing (docker-compose)
```bash
cd project/
ENVIRONMENT=local ./scripts/run-k6-tests.sh constant-load
```

Or let it auto-detect:
```bash
cd project/
./scripts/run-k6-tests.sh constant-load
# Will auto-detect local if no kubectl/k8s cluster
```

**Requirements:**
- k6 installed locally
- docker-compose running in `../socialNetwork/` directory
- Application accessible at `http://localhost:8080`

#### For GKE Testing
```bash
cd project/
ENVIRONMENT=gke ./scripts/run-k6-tests.sh constant-load
```

Or let it auto-detect:
```bash
cd project/
# Make sure kubectl is configured for your GKE cluster
./scripts/run-k6-tests.sh constant-load
# Will auto-detect GKE if kubectl is configured
```

**Requirements:**
- k6 installed locally
- kubectl configured and pointing to GKE cluster
- Application deployed to GKE (via `deploy-gke.sh`)
- LoadBalancer service provisioned (may take 1-2 minutes)

#### Manual URL Override
```bash
cd project/
BASE_URL=http://1.2.3.4:8080 ./scripts/run-k6-tests.sh constant-load
```

### Auto-Detection
The script automatically detects the environment:
- **GKE**: If `kubectl` is available and connected to a cluster
- **Local**: Otherwise

It then:
- **GKE**: Gets the LoadBalancer IP from Kubernetes
- **Local**: Uses `http://localhost:8080`

### Available Test Types
- `constant-load` - Steady load test
- `peak-test` - Traffic spike test
- `stress-test` - Gradual ramp-up test
- `endurance-test` - Long-duration test (5+ hours)
- `all` - Run all tests except endurance

---

## Script: `setup-monitoring.sh`

### What It Does
Sets up Prometheus and Grafana for monitoring in Kubernetes.

### Important Limitation
**This script is KUBERNETES ONLY** - it does not work with local docker-compose.

### Usage

#### For GKE
```bash
cd project/
# Make sure kubectl is configured for your GKE cluster
./scripts/setup-monitoring.sh
```

**Requirements:**
- kubectl configured and pointing to GKE cluster
- Appropriate permissions to create namespaces and deployments

#### For Local docker-compose
**Not supported.** The monitoring stack (Prometheus/Grafana) requires Kubernetes.

**Alternatives for local monitoring:**
- Use Docker stats: `docker stats`
- Use docker-compose metrics (if configured)
- Skip monitoring for local development

### What It Deploys
1. **Prometheus** - Metrics collection
   - Access via: `kubectl port-forward -n monitoring svc/prometheus 9090:9090`
   - Then visit: `http://localhost:9090`

2. **Grafana** - Metrics visualization
   - Access via: `kubectl port-forward -n monitoring svc/grafana 3000:3000`
   - Then visit: `http://localhost:3000`
   - Default credentials: `admin/admin`

---

## Helper Script: `get-endpoint.sh`

### What It Does
Quick helper to get the application endpoint URL.

### Usage

#### Auto-detect
```bash
cd project/
./scripts/get-endpoint.sh
```

#### Force GKE
```bash
cd project/
./scripts/get-endpoint.sh gke
```

#### Force Local
```bash
cd project/
./scripts/get-endpoint.sh local
```

### Output
Prints the endpoint URL that you can use for testing:
```
http://1.2.3.4:8080  # GKE LoadBalancer IP
# or
http://localhost:8080  # Local
```

---

## Complete Workflows

### Workflow 1: Local Development & Testing

```bash
# 1. Start application locally
cd socialNetwork/
docker-compose up -d

# 2. Run k6 tests
cd ../project/
./scripts/run-k6-tests.sh constant-load

# 3. Check results
ls -la k6-results/
```

**Note:** Monitoring is not available for local docker-compose.

---

### Workflow 2: GKE Deployment & Testing

```bash
# 1. Deploy to GKE
cd project/
./scripts/deploy-gke.sh

# 2. Wait for LoadBalancer to be ready (1-2 minutes)
# Check status:
kubectl get service nginx-thrift-service

# 3. Set up monitoring
./scripts/setup-monitoring.sh

# 4. Get endpoint
./scripts/get-endpoint.sh

# 5. Run k6 tests
./scripts/run-k6-tests.sh constant-load

# 6. Access monitoring
# Prometheus:
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Then visit http://localhost:9090

# Grafana:
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Then visit http://localhost:3000 (admin/admin)
```

---

## Troubleshooting

### k6 Tests Fail to Connect

**Local:**
- Check docker-compose is running: `cd socialNetwork && docker-compose ps`
- Verify port 8080 is accessible: `curl http://localhost:8080`

**GKE:**
- Check LoadBalancer is ready: `kubectl get service nginx-thrift-service`
- Wait 1-2 minutes for LoadBalancer IP to be assigned
- Verify pods are running: `kubectl get pods`
- Check service endpoints: `kubectl get endpoints nginx-thrift-service`

### Monitoring Setup Fails

- Verify kubectl is configured: `kubectl cluster-info`
- Check you have permissions: `kubectl auth can-i create deployments -n monitoring`
- Check if namespace exists: `kubectl get namespace monitoring`

### Auto-Detection Issues

If auto-detection doesn't work:
- **Force local**: `ENVIRONMENT=local ./scripts/run-k6-tests.sh constant-load`
- **Force GKE**: `ENVIRONMENT=gke ./scripts/run-k6-tests.sh constant-load`
- **Manual URL**: `BASE_URL=http://your-url:8080 ./scripts/run-k6-tests.sh constant-load`

---

## Summary Table

| Script | Local (docker-compose) | GKE (Kubernetes) |
|--------|------------------------|------------------|
| `run-k6-tests.sh` | ✅ Works | ✅ Works |
| `setup-monitoring.sh` | ❌ Not supported | ✅ Works |
| `get-endpoint.sh` | ✅ Works | ✅ Works |
| `deploy-gke.sh` | ❌ Not applicable | ✅ Works |

---

## Quick Reference

```bash
# Local testing
cd socialNetwork && docker-compose up
cd ../project && ./scripts/run-k6-tests.sh constant-load

# GKE deployment
cd project && ./scripts/deploy-gke.sh
cd project && ./scripts/setup-monitoring.sh
cd project && ./scripts/run-k6-tests.sh constant-load
```

