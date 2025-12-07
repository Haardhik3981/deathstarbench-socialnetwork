# CI/CD Automation Setup Guide

## Overview

This guide explains how to set up CI/CD automation for deploying the Social Network application to Kubernetes using GitHub Actions.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub Repository                                          │
│                                                              │
│  Push to main/master → Triggers CI/CD Pipeline              │
│                    ↓                                         │
│  ┌─────────────────────────────────────────────┐           │
│  │  GitHub Actions Workflow                     │           │
│  │                                               │           │
│  │  1. Lint Helm Chart                           │           │
│  │  2. Build Images (optional)                   │           │
│  │  3. Deploy to Kubernetes                      │           │
│  │  4. Apply HPA Configuration                   │           │
│  │  5. Run Smoke Tests                           │           │
│  └─────────────────────────────────────────────┘           │
│                    ↓                                         │
│  Kubernetes Cluster (Nautilus)                              │
│  └─ Social Network Application Deployed                     │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **GitHub Repository** with the Social Network code
2. **Kubernetes Cluster Access** (Nautilus cluster)
3. **kubectl** configured locally
4. **Helm** installed

## Setup Steps

### Step 1: Configure GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these secrets:

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `KUBECONFIG` | Kubernetes cluster config | `cat ~/.kube/config \| base64` |
| `REGISTRY_URL` | Container registry URL (if using) | Your registry URL |
| `REGISTRY_USERNAME` | Registry username (if using) | Your registry username |
| `REGISTRY_PASSWORD` | Registry password (if using) | Your registry password |

**To get KUBECONFIG:**
```bash
# Export your kubeconfig
cat ~/.kube/config | base64 -w 0

# Copy the output and paste into GitHub Secrets as KUBECONFIG
```

### Step 2: Verify Workflow File

The workflow file is located at:
`.github/workflows/deploy-social-network.yml`

It includes:
- ✅ Helm chart linting
- ✅ Kubernetes deployment
- ✅ HPA application
- ✅ Smoke tests

### Step 3: Test the Pipeline

#### Option A: Manual Trigger

1. Go to GitHub Actions tab
2. Click "Deploy Social Network to Kubernetes"
3. Click "Run workflow"
4. Select branch and click "Run workflow"

#### Option B: Push to Trigger

```bash
# Make a small change and push
git checkout -b test-cicd
echo "# Test" >> README.md
git add README.md
git commit -m "Test CI/CD pipeline"
git push origin test-cicd

# Merge to main to trigger deployment
```

## Workflow Jobs

### Job 1: Build Images (Optional)

**Purpose**: Build and push container images to registry

**When it runs**: Only on push to main/master

**Note**: Currently skipped (using public images). Uncomment if you need custom builds.

### Job 2: Lint Helm Chart

**Purpose**: Validate Helm chart syntax

**When it runs**: On every push and PR

**Checks**:
- Helm chart syntax
- Kubernetes manifest validation

### Job 3: Deploy to Kubernetes

**Purpose**: Deploy application using Helm

**When it runs**: Only on push to main/master

**Steps**:
1. Creates namespace if needed
2. Runs `helm upgrade --install`
3. Waits for pods to be ready
4. Verifies deployment

### Job 4: Apply HPA Configuration

**Purpose**: Apply Horizontal Pod Autoscaler

**When it runs**: After successful deployment

**Applies**: `scripts/hpa-config.yaml`

### Job 5: Smoke Tests

**Purpose**: Verify deployment is working

**When it runs**: After successful deployment

**Tests**:
- Service discovery
- Pod health
- Basic connectivity

## Customization

### Change Deployment Namespace

Edit `.github/workflows/deploy-social-network.yml`:

```yaml
env:
  NAMESPACE: cse239fall2025
```

### Add Custom Helm Values

Edit the deploy step:

```yaml
- name: Deploy with Helm
  run: |
    helm upgrade --install dsb-socialnetwork \
      ${{ env.HELM_CHART_PATH }} \
      --namespace ${{ env.NAMESPACE }} \
      --set global.replicas=2 \
      --set global.resources.requests.cpu=500m \
      --set global.resources.requests.memory=512Mi
```

### Add More Tests

Add to smoke-tests job:

```yaml
- name: Test API endpoints
  run: |
    kubectl port-forward svc/nginx-thrift 8080:8080 -n ${{ env.NAMESPACE }} &
    sleep 5
    curl -f http://localhost:8080/wrk2-api/home-timeline/read?user_id=1&start=0&stop=10
```

## Monitoring CI/CD

### View Workflow Runs

1. Go to GitHub → Actions tab
2. Click on a workflow run
3. View logs for each job

### Common Issues

#### Issue: "kubectl: command not found"
**Solution**: The workflow installs kubectl automatically. If it fails, check the setup-kubectl action.

#### Issue: "Error: connection refused"
**Solution**: 
- Verify KUBECONFIG secret is correct
- Check cluster access: `kubectl cluster-info`

#### Issue: "Error: namespace not found"
**Solution**: The workflow creates the namespace automatically. Check if you have permissions.

#### Issue: "Error: helm chart not found"
**Solution**: Verify `HELM_CHART_PATH` in workflow matches your chart location.

## Advanced: Multi-Environment Deployment

### Create Staging Environment

Create `.github/workflows/deploy-staging.yml`:

```yaml
name: Deploy to Staging

on:
  push:
    branches: [develop]

env:
  NAMESPACE: cse239fall2025-staging
  HELM_CHART_PATH: Helm/DeathStarBench/socialNetwork/helm-chart/socialnetwork

jobs:
  deploy:
    # ... same as main workflow but with staging namespace
```

### Create Production Environment

Create `.github/workflows/deploy-production.yml`:

```yaml
name: Deploy to Production

on:
  workflow_dispatch:  # Manual trigger only
    inputs:
      version:
        description: 'Image version/tag'
        required: true

env:
  NAMESPACE: cse239fall2025-production
  HELM_CHART_PATH: Helm/DeathStarBench/socialNetwork/helm-chart/socialnetwork

jobs:
  deploy:
    # ... production deployment with approvals
```

## Integration with Monitoring

The CI/CD pipeline can be extended to:

1. **Deploy monitoring stack**:
   ```yaml
   - name: Deploy Prometheus/Grafana
     run: |
       kubectl apply -f monitoring/ -n ${{ env.NAMESPACE }}
   ```

2. **Run load tests**:
   ```yaml
   - name: Run k6 load test
     run: |
       k6 run scripts/k6-load-test.js
   ```

## Best Practices

1. ✅ **Use secrets** for sensitive data (KUBECONFIG, passwords)
2. ✅ **Test in staging** before production
3. ✅ **Use workflow_dispatch** for production (manual approval)
4. ✅ **Monitor deployments** in Grafana after CI/CD runs
5. ✅ **Rollback plan**: Keep previous Helm releases for quick rollback

## Rollback

If deployment fails, rollback:

```bash
# List releases
helm list -n cse239fall2025

# Rollback to previous version
helm rollback dsb-socialnetwork -n cse239fall2025

# Or delete and redeploy
helm uninstall dsb-socialnetwork -n cse239fall2025
```

## Summary

✅ **CI/CD Pipeline**: Automated deployment on git push  
✅ **Helm Integration**: Uses Helm for deployment  
✅ **HPA Automation**: Automatically applies autoscaling  
✅ **Smoke Tests**: Verifies deployment success  
✅ **Multi-Environment**: Can be extended for staging/production

