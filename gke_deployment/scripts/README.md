# Scripts Directory

Helper scripts for managing, testing, and troubleshooting the DeathStarBench deployment.

## Essential Scripts

### Pre-Test Setup

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `reset-all-databases.sh` | ⭐ Resets all MongoDB databases | **Before every test** |
| `verify-system-ready.sh` | ⭐ Comprehensive system verification | **Before every test** |
| `apply-all-deployments.sh` | Apply all deployment YAML files | After editing deployments |

### Running Tests

| Script | Purpose | Usage |
|--------|---------|-------|
| `run-test-with-metrics.sh` | Run k6 tests with metrics collection | `./run-test-with-metrics.sh <test-name>` |
| `extract-k6-metrics.sh` | Extract metrics from k6 results | `./extract-k6-metrics.sh <summary-file>` |

### Pod Management

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `quick-restart-all-pods.sh` | Restart all service pods | After configuration changes |
| `restart-pods-with-new-config.sh` | Restart with new config | Legacy - use `quick-restart-all-pods.sh` |

## Deployment Scripts

| Script | Purpose |
|--------|---------|
| `deploy-gke.sh` | Deploy to Google Kubernetes Engine |
| `deploy-nautilus.sh` | Deploy to Nautilus cluster |
| `verify-deployment.sh` | Basic deployment verification (legacy) |

## Database Management

| Script | Purpose |
|--------|---------|
| `reset-all-databases.sh` | ⭐ Reset all MongoDB databases (most important) |
| `clear-nonessential-memory.sh` | Free memory by scaling down services |

## Cleanup Scripts

| Script | Purpose |
|--------|---------|
| `deep-cleanup.sh` | Deep cleanup of cluster resources |
| `quick-cleanup.sh` | Quick cleanup (project root) |

## Recommended Workflow

### Before Every Test
```bash
# 1. Reset databases (CRITICAL)
./scripts/reset-all-databases.sh

# 2. Verify system
./scripts/verify-system-ready.sh

# 3. Start port-forward (separate terminal)
kubectl port-forward svc/nginx-thrift-service 8080:8080
```

### Running Tests
```bash
# Run test with metrics
./scripts/run-test-with-metrics.sh sweet-test
```

### After Configuration Changes
```bash
# Apply updated deployments
./scripts/apply-all-deployments.sh

# Restart pods
./scripts/quick-restart-all-pods.sh
```

## Script Categories

| Category | Scripts | Frequency |
|----------|---------|-----------|
| **Essential** | `reset-all-databases.sh`, `verify-system-ready.sh`, `run-test-with-metrics.sh` | Every test |
| **Deployment** | `apply-all-deployments.sh`, `deploy-gke.sh`, `deploy-nautilus.sh` | As needed |
| **Maintenance** | `quick-restart-all-pods.sh`, `deep-cleanup.sh` | As needed |
| **Utilities** | `extract-k6-metrics.sh` | After tests |

## Notes

- ⭐ **Most Important**: `reset-all-databases.sh` and `verify-system-ready.sh` - run before every test
- Use `apply-all-deployments.sh` instead of `kubectl apply -f *.yaml` (handles wildcard issues)
- All scripts include error handling and colored output
- See individual script comments for detailed usage
