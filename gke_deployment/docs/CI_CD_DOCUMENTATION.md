# CI/CD Pipeline Documentation

## Overview

This document describes the Continuous Integration/Continuous Deployment (CI/CD) pipeline for the DeathStarBench Social Network project. The pipeline automates validation, testing, security scanning, and deployment of the Kubernetes-based microservices application.

## Pipeline Location

The CI/CD pipeline is defined in:
- **Workflow File**: `.github/workflows/project-ci-cd.yaml`
- **Documentation**: `project/CI_CD_DOCUMENTATION.md` (this file)

## Pipeline Triggers

The pipeline runs automatically on:

1. **Push Events**: When code is pushed to `main`, `master`, or `develop` branches
   - Only triggers if files in `project/` directory are changed
   - Validates and tests changes

2. **Pull Request Events**: When a PR is opened or updated
   - Validates changes before merging
   - Does not deploy (deployment requires manual approval)

3. **Manual Dispatch**: Can be triggered manually via GitHub Actions UI
   - Options to skip tests or enable deployment
   - Useful for testing or deploying on-demand

## Pipeline Jobs

### 1. Validate Kubernetes Manifests

**Purpose**: Validates that all Kubernetes YAML manifests are syntactically correct and can be applied.

**Steps**:
- Checks out the code
- Installs `kubectl`
- Validates all YAML files in `project/kubernetes/` using `kubectl apply --dry-run`
- Checks for common issues (missing image tags, hardcoded secrets)

**Output**: 
- ✅ Pass: All manifests are valid
- ❌ Fail: Invalid YAML or Kubernetes configuration errors

**Duration**: ~1-2 minutes

### 2. Lint Shell Scripts

**Purpose**: Ensures all shell scripts follow best practices and don't have syntax errors.

**Steps**:
- Checks out the code
- Installs `shellcheck` (shell script linter)
- Lints all `.sh` files in `project/scripts/`

**Output**:
- ✅ Pass: All scripts pass linting
- ❌ Fail: Scripts have syntax errors or best practice violations

**Duration**: ~1 minute

### 3. Test k6 Load Tests

**Purpose**: Validates k6 load test scripts for syntax errors and ensures they're ready to run.

**Steps**:
- Checks out the code
- Installs k6 (load testing tool)
- Validates k6 test files exist
- Validates k6 test syntax using `k6 inspect`

**Output**:
- ✅ Pass: All k6 tests have valid syntax
- ⚠️ Note: Full tests require a running Kubernetes cluster (not run in CI)

**Duration**: ~1-2 minutes

**Note**: Full k6 load tests are not executed in CI because they require:
- A running Kubernetes cluster
- Deployed services
- Port forwarding or external access
- Significant time (some tests run for hours)

To run full tests, deploy to a cluster and run manually:
```bash
kubectl port-forward svc/nginx-thrift-service 8080:8080
k6 run project/k6-tests/constant-load.js
```

### 4. Security Scan

**Purpose**: Scans the project for security vulnerabilities.

**Steps**:
- Checks out the code
- Runs Trivy security scanner on `project/` directory
- Scans for CRITICAL and HIGH severity vulnerabilities
- Uploads results to GitHub Security tab

**Output**:
- ✅ Pass: No critical or high severity vulnerabilities found
- ⚠️ Warning: Vulnerabilities found (review in GitHub Security tab)

**Duration**: ~2-3 minutes

### 5. Deploy to Kubernetes (Optional)

**Purpose**: Deploys the application to a Kubernetes cluster.

**When it runs**:
- Manual workflow dispatch with `deploy: true`
- Push to `main` or `master` branch (if configured)

**Steps**:
- Checks out the code
- Configures kubectl (using secrets)
- Verifies cluster connection
- Deploys ConfigMaps, Deployments, and Services
- Waits for deployments to be ready
- Generates deployment summary

**Prerequisites**:
- Kubernetes cluster credentials configured as GitHub secrets
- Cluster must be accessible from GitHub Actions runners

**Duration**: ~5-10 minutes

### 6. CI/CD Summary

**Purpose**: Provides an overview of all pipeline jobs and their status.

**Output**: Summary table showing the status of all jobs

## GitHub Secrets Configuration

To enable deployment, configure the following secrets in GitHub:

### Option 1: Direct kubeconfig

```
KUBECONFIG
```
- Full kubeconfig file content
- Base64 encoded or plain text

### Option 2: Google Kubernetes Engine (GKE)

```
GKE_SA_KEY          # Service account key (JSON, base64 encoded)
GKE_CLUSTER_NAME    # Name of the GKE cluster
GKE_ZONE            # GKE cluster zone (e.g., us-central1-a)
GKE_PROJECT_ID      # GCP project ID
```

### Option 3: Docker Registry (if building images)

```
DOCKER_REGISTRY_LOGIN     # Docker registry username
DOCKER_REGISTRY_PASSWORD   # Docker registry password
```

## Setting Up Secrets

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret with the appropriate name and value

## Manual Workflow Dispatch

To manually trigger the pipeline:

1. Go to **Actions** tab in GitHub
2. Select **Project CI/CD Pipeline**
3. Click **Run workflow**
4. Choose options:
   - **Skip tests**: Skip k6 test validation
   - **Deploy**: Deploy to Kubernetes cluster (requires secrets)

## Pipeline Status

You can view pipeline status:

- **GitHub Actions Tab**: See all workflow runs
- **Pull Request Checks**: See validation status on PRs
- **Commit Status**: See status badges on commits

## Troubleshooting

### Pipeline Fails on Validation

**Issue**: Kubernetes manifest validation fails

**Solutions**:
- Check YAML syntax (indentation, quotes, etc.)
- Verify all required fields are present
- Review error messages in the workflow logs
- Test locally: `kubectl apply --dry-run -f <file>`

### Pipeline Fails on Linting

**Issue**: Shell script linting fails

**Solutions**:
- Install shellcheck locally: `brew install shellcheck` (macOS)
- Run locally: `shellcheck project/scripts/*.sh`
- Fix issues reported by shellcheck
- Review shellcheck documentation for best practices

### Deployment Fails

**Issue**: Cannot connect to Kubernetes cluster

**Solutions**:
- Verify secrets are configured correctly
- Check cluster is accessible from GitHub Actions IPs
- Verify service account has necessary permissions
- Review kubectl connection logs in workflow output

### Security Scan Finds Vulnerabilities

**Issue**: Trivy reports security vulnerabilities

**Solutions**:
- Review vulnerabilities in GitHub Security tab
- Update dependencies to patched versions
- Review if vulnerabilities are false positives
- Document accepted risks if necessary

## Best Practices

### For Developers

1. **Test Locally First**: Run validation and linting locally before pushing
   ```bash
   # Validate manifests
   kubectl apply --dry-run -f project/kubernetes/
   
   # Lint scripts
   shellcheck project/scripts/*.sh
   
   # Validate k6 tests
   k6 inspect project/k6-tests/*.js
   ```

2. **Small, Focused Changes**: Make small, focused commits to make debugging easier

3. **Review Pipeline Logs**: Check pipeline logs if validation fails

4. **Update Documentation**: Keep documentation in sync with code changes

### For CI/CD Maintenance

1. **Regular Updates**: Keep GitHub Actions versions updated
2. **Monitor Costs**: Be aware of GitHub Actions minutes usage
3. **Review Security**: Regularly review security scan results
4. **Test Changes**: Test pipeline changes in a branch before merging

## Pipeline Customization

### Adding New Validation Steps

Edit `.github/workflows/project-ci-cd.yaml` and add a new job:

```yaml
new-validation:
  name: New Validation Step
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run validation
      run: |
        # Your validation commands here
```

### Modifying Deployment Steps

Edit the `deploy` job in the workflow file to customize deployment behavior.

### Adding Notifications

Add notification steps to notify on success/failure:

```yaml
- name: Notify on failure
  if: failure()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: 'Pipeline failed!'
```

## Related Documentation

- **Deployment Guide**: `project/DEPLOYMENT_GUIDE.md`
- **k6 Tests**: `project/k6-tests/README.md`
- **Scripts Usage**: `project/SCRIPTS_USAGE.md`
- **Autoscaling Guide**: `project/kubernetes/autoscaling/README.md`

## Support

For issues or questions:
1. Check this documentation
2. Review workflow logs in GitHub Actions
3. Check related documentation files
4. Review GitHub Issues (if applicable)

## Changelog

### Version 1.0 (Initial Release)
- Basic validation and linting
- k6 test syntax validation
- Security scanning with Trivy
- Optional Kubernetes deployment
- Manual workflow dispatch support

