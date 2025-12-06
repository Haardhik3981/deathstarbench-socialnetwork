# Scripts Directory Reference

This directory contains scripts for managing, testing, and troubleshooting the DeathStarBench social network application.

## Essential Scripts (Use Regularly)

### Pre-Test Setup
- **`reset-all-databases.sh`** ⭐ **MOST IMPORTANT**
  - Resets ALL MongoDB databases (clears stale data)
  - **Run this between every test** to prevent duplicate key errors
  - Resets: user-mongodb, social-graph-mongodb, and all other MongoDB databases

- **`verify-system-ready.sh`** ⭐ **CRITICAL**
  - Comprehensive system verification before tests
  - Checks pods, services, databases, connectivity, MongoDB index loops
  - **Run this before every test** to ensure system is ready

- **`quick-restart-all-pods.sh`**
  - Restarts all service pods (use after configuration changes)
  - Faster than `restart-pods-with-new-config.sh`

### Running Tests
- **`run-k6-tests.sh`**
  - Main script for running k6 load tests
  - Usage: `./run-k6-tests.sh <test-name>`
  - Tests: quick-test, peak-test

- **`run-test-with-metrics.sh`**
  - Runs k6 tests with additional metrics collection
  - Alternative to `run-k6-tests.sh` with more detailed output

### Database Management
- **`reset-mongodb-database.sh`**
  - Resets only user-mongodb (for targeted resets)
  - Use `reset-all-databases.sh` for complete reset

- **`reset-social-graph-mongodb.sh`**
  - Resets only social-graph-mongodb (for targeted resets)
  - Use `reset-all-databases.sh` for complete reset

## Diagnostic Scripts (Use When Troubleshooting)

### Quick Diagnostics
- **`quick-cluster-check.sh`**
  - Quick health check of cluster (API, metrics-server, HPA)

- **`quick-diagnosis.sh`**
  - Fast diagnostic check for common issues

- **`diagnose-cluster-overload.sh`**
  - Comprehensive cluster resource analysis
  - Checks nodes, pods, HPAs, resource usage

- **`diagnose-failures.sh`**
  - Detailed failure analysis
  - Checks logs, events, pod status

### Service Checks
- **`check-service-connections.sh`**
  - Tests service-to-service connectivity

- **`check-node-capacity.sh`**
  - Checks node CPU and memory allocation

- **`verify-hpa-metrics.sh`**
  - Verifies HPA metrics are being collected

- **`check-prometheus-metrics.sh`**
  - Checks Prometheus metrics availability

### Pod Management
- **`debug-pods.sh`**
  - Debug information for pods

- **`cleanup-pending-pods.sh`**
  - Deletes pods stuck in Pending state

- **`cleanup-all-duplicates.sh`** / **`cleanup-duplicate-pods.sh`**
  - Removes duplicate pods (rarely needed)

## Deployment Scripts

- **`deploy-gke.sh`**
  - Deploys to Google Kubernetes Engine (GKE)

- **`deploy-nautilus.sh`**
  - Deploys to Nautilus cluster

## Autoscaling Scripts

- **`run-autoscaling-experiments.sh`**
  - Runs different autoscaling experiment configurations

- **`apply-vpa-experiment.sh`**
  - Applies VPA (Vertical Pod Autoscaler) configurations

- **`verify-vpa-applied.sh`** / **`verify-vpa-setup.sh`**
  - Verifies VPA is configured correctly

- **`minimal-autoscaling-setup.sh`**
  - Sets up minimal autoscaling (only critical services)

- **`free-up-cluster-capacity.sh`**
  - Reduces resource requests to free up cluster capacity

## Utility Scripts

- **`extract-k6-metrics.sh`**
  - Extracts metrics from k6 test results

- **`pre-test-checklist.sh`**
  - Pre-test verification checklist (use `verify-system-ready.sh` instead)

- **`verify-deployment.sh`**
  - Verifies deployment status

- **`health-check.sh`**
  - General health check (use `verify-system-ready.sh` instead)

- **`restart-all-services.sh`**
  - Restarts deployments (use `quick-restart-all-pods.sh` instead)

- **`restart-pods-with-new-config.sh`**
  - Restarts pods with new config (use `quick-restart-all-pods.sh` instead)

## Cleanup Scripts

- **`cleanup-storage.sh`**
  - Cleans up storage resources

- **`deep-cleanup.sh`**
  - Deep cleanup of cluster resources

- **`clear-nonessential-memory.sh`**
  - Frees up memory by scaling down non-essential services

## Fix Scripts (One-Time Use)

- **`fix-all-readiness-probes.sh`**
  - Fixes readiness probes in all deployments (already applied)

- **`fix-readiness-probes.sh`**
  - Fixes readiness probes (single service, already applied)

- **`fix-mongodb-errors.sh`**
  - Fixes MongoDB errors (use `reset-all-databases.sh` instead)

## Recommended Workflow

### Before Every Test
```bash
# 1. Reset databases (CRITICAL)
./reset-all-databases.sh

# 2. Verify system
./verify-system-ready.sh

# 3. Start port-forward (in separate terminal)
kubectl port-forward -n default svc/nginx-thrift-service 8080:8080
```

### Running Tests
```bash
# Run test
./run-k6-tests.sh quick-test
# or
./run-k6-tests.sh peak-test
```

### Between Tests
```bash
# Reset everything
./reset-all-databases.sh
./verify-system-ready.sh
```

### When Troubleshooting
```bash
# Quick check
./quick-cluster-check.sh

# Detailed diagnosis
./diagnose-cluster-overload.sh
./diagnose-failures.sh

# Check specific issue
./check-service-connections.sh
./check-node-capacity.sh
```

## Script Categories Summary

| Category | Scripts | When to Use |
|----------|---------|-------------|
| **Essential** | `reset-all-databases.sh`, `verify-system-ready.sh`, `quick-restart-all-pods.sh`, `run-k6-tests.sh` | Before/during/after every test |
| **Diagnostic** | `quick-cluster-check.sh`, `diagnose-cluster-overload.sh`, `diagnose-failures.sh` | When troubleshooting |
| **Database** | `reset-mongodb-database.sh`, `reset-social-graph-mongodb.sh` | Targeted database resets |
| **Deployment** | `deploy-gke.sh`, `deploy-nautilus.sh` | Initial deployment |
| **Autoscaling** | `run-autoscaling-experiments.sh`, `apply-vpa-experiment.sh` | Autoscaling experiments |
| **Cleanup** | `cleanup-pending-pods.sh`, `cleanup-storage.sh` | Cleanup tasks |
| **Legacy** | `pre-test-checklist.sh`, `health-check.sh`, `restart-all-services.sh` | Use newer alternatives |

## Notes

- ⭐ **Most Important**: `reset-all-databases.sh` and `verify-system-ready.sh`
- Many scripts are for one-time fixes or specific troubleshooting scenarios
- Use the Essential scripts for regular testing workflow
- Diagnostic scripts are helpful when things go wrong
- Legacy scripts may be outdated; use recommended alternatives

