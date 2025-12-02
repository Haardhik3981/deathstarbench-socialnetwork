#!/bin/bash

# Script to debug config mount issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Get a pod that's running or recently crashed
POD_NAME=$(kubectl get pods | grep compose-post-service | grep -E "Running|Error|CrashLoopBackOff" | head -1 | awk '{print $1}')

if [ -z "$POD_NAME" ] || [ "$POD_NAME" == "NAME" ]; then
    print_warn "No compose-post-service pod found to check"
    exit 1
fi

print_step "=== Step 1: Check ConfigMap Exists ==="
print_info "Checking if deathstarbench-config ConfigMap exists..."
kubectl get configmap deathstarbench-config
echo ""

print_step "=== Step 2: Check ConfigMap Contents ==="
print_info "Checking if jaeger-config.yml exists in ConfigMap..."
kubectl get configmap deathstarbench-config -o jsonpath='{.data.jaeger-config\.yml}' | head -5
if [ $? -eq 0 ]; then
    echo ""
    print_info "✓ jaeger-config.yml exists in ConfigMap"
else
    print_warn "✗ jaeger-config.yml NOT found in ConfigMap"
fi

echo ""
print_step "=== Step 3: Check Pod Volume Mounts ==="
print_info "Checking volume mounts in pod: $POD_NAME"
kubectl describe pod "$POD_NAME" | grep -A 10 "Mounts:" | head -15

echo ""
print_step "=== Step 4: Try to Check Files in Pod (if pod is running) ==="
if kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}' | grep -q Running; then
    print_info "Pod is running. Checking if files are mounted correctly..."
    kubectl exec "$POD_NAME" -- ls -la /social-network-microservices/config/ 2>&1 || print_warn "Could not exec into pod (may have crashed)"
else
    print_info "Pod is not running (status: $(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}'))"
    print_info "Cannot check files directly, but we can check deployment configuration"
fi

echo ""
print_step "=== Step 5: Check Deployment Configuration ==="
print_info "Checking volumeMounts in deployment..."
kubectl get deployment compose-post-service-deployment -o yaml | grep -A 15 "volumeMounts:" | head -20

echo ""
print_step "=== Summary ==="
print_info "This will help identify if:"
echo "  1. ConfigMap has the files"
echo "  2. Deployment mounts them correctly"
echo "  3. Files are accessible in the pod"

