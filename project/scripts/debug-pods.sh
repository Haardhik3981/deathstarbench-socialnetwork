#!/bin/bash

# Diagnostic script to debug pod crashes and deployment issues

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
print_info "POD DIAGNOSTICS"
echo "=========================================="
echo ""

# Check pod status
print_info "Checking pod status..."
kubectl get pods --sort-by=.status.startTime
echo ""

# Check for CrashLoopBackOff pods
print_info "Pods in CrashLoopBackOff:"
CRASHED_PODS=$(kubectl get pods -o jsonpath='{range .items[?(@.status.containerStatuses[0].state.waiting.reason=="CrashLoopBackOff")]}{.metadata.name}{"\n"}{end}')
if [ -z "$CRASHED_PODS" ]; then
    print_info "No pods in CrashLoopBackOff"
else
    echo "$CRASHED_PODS"
    echo ""
    print_info "Getting logs from crashed pods (first 50 lines)..."
    echo "$CRASHED_PODS" | head -3 | while read pod; do
        if [ -n "$pod" ]; then
            echo ""
            print_warn "=== Logs from $pod ==="
            kubectl logs "$pod" --tail=50 2>&1 | head -50
            echo ""
        fi
    done
fi
echo ""

# Check for Pending pods
print_info "Pods in Pending state:"
PENDING_PODS=$(kubectl get pods -o jsonpath='{range .items[?(@.status.phase=="Pending")]}{.metadata.name}{"\n"}{end}')
if [ -z "$PENDING_PODS" ]; then
    print_info "No pods in Pending state"
else
    echo "$PENDING_PODS"
    echo ""
    print_info "Checking why pods are pending..."
    echo "$PENDING_PODS" | head -3 | while read pod; do
        if [ -n "$pod" ]; then
            echo ""
            print_warn "=== Events for $pod ==="
            kubectl describe pod "$pod" | grep -A 10 "Events:" || true
            echo ""
        fi
    done
fi
echo ""

# Check database pods
print_info "Database pod status:"
kubectl get pods | grep -E "(mongodb|redis|memcached)" || print_warn "No database pods found"
echo ""

# Check ConfigMap
print_info "Checking ConfigMap..."
if kubectl get configmap deathstarbench-config &>/dev/null; then
    print_info "ConfigMap 'deathstarbench-config' exists"
    kubectl get configmap deathstarbench-config -o jsonpath='{.data.service-config\.json}' | head -20 || true
else
    print_error "ConfigMap 'deathstarbench-config' NOT FOUND!"
fi
echo ""

# Check services
print_info "Service endpoints status:"
kubectl get endpoints | grep -E "(user-service|social-graph-service|nginx-thrift)" | head -10
echo ""

# Check resource usage
print_info "Node resource usage:"
kubectl top nodes 2>/dev/null || print_warn "Metrics server not available"
echo ""

# Check for common issues
print_info "Checking for common issues..."

# Check if binaries exist in image (sample check)
print_info "Checking if service binaries exist in image..."
SAMPLE_POD=$(kubectl get pods -l app=user-service --field-selector=status.phase!=Pending -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$SAMPLE_POD" ]; then
    print_info "Checking binary path in pod: $SAMPLE_POD"
    kubectl exec "$SAMPLE_POD" -- ls -la /social-network-microservices/build/UserService 2>&1 || print_error "Binary not found at expected path!"
else
    print_warn "No running user-service pod found to check binary path"
fi
echo ""

# Check image pull status
print_info "Checking image pull status..."
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].image}{"\t"}{.status.containerStatuses[0].imagePullPolicy}{"\t"}{.status.containerStatuses[0].ready}{"\n"}{end}' | head -10
echo ""

print_info "Diagnostics complete!"
print_info "To get detailed logs from a specific pod:"
print_info "  kubectl logs <pod-name>"
print_info "To describe a pod:"
print_info "  kubectl describe pod <pod-name>"

