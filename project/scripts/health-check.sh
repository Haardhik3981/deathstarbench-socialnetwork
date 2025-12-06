#!/bin/bash

# Health and Utilization Check Script
# 
# WHAT THIS DOES:
# This script performs a comprehensive health and resource utilization check of your
# Kubernetes deployment. It shows CPU, memory, and network usage for all pods and
# services, helping you ensure you're starting tests from a clean baseline.
#
# KEY FEATURES:
# - Pod status and readiness checks
# - CPU and memory usage for all pods
# - Network metrics (if available)
# - Service endpoint health
# - Resource request/limit comparison
# - Overall health summary
#
# USAGE:
#   ./scripts/health-check.sh
#   ./scripts/health-check.sh --namespace default
#   ./scripts/health-check.sh --detailed

# Don't exit on error - we want to continue checking even if some commands fail
set +e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default namespace
NAMESPACE="${NAMESPACE:-default}"
DETAILED=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--namespace NAMESPACE] [--detailed]"
            echo ""
            echo "Options:"
            echo "  --namespace NAMESPACE  Kubernetes namespace (default: default)"
            echo "  --detailed             Show detailed resource information"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
print_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_subsection() {
    echo -e "${CYAN}─── $1 ───${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "  $1"
}

# Track overall health
HEALTHY=true
WARNINGS=0
ERRORS=0

# Start of script
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Kubernetes Deployment Health & Utilization Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Namespace: $NAMESPACE"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check kubectl connection
print_section "1. Cluster Connection"
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    print_info "Make sure kubectl is configured correctly"
    exit 1
fi

CLUSTER_INFO=$(kubectl cluster-info | head -n 1 | sed 's/.*is running at //')
print_success "Connected to cluster"
print_info "Cluster: $CLUSTER_INFO"
print_info "Context: $(kubectl config current-context 2>/dev/null || echo 'unknown')"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_error "Namespace '$NAMESPACE' does not exist"
    exit 1
fi

# Check if metrics-server is available
print_section "2. Metrics Server Availability"
METRICS_AVAILABLE=false
if kubectl top nodes &> /dev/null 2>&1; then
    METRICS_AVAILABLE=true
    print_success "Metrics server is available"
    print_info "CPU and memory metrics will be shown"
else
    print_warn "Metrics server is not available"
    print_info "CPU and memory usage will not be shown"
    print_info "Install metrics-server: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    ((WARNINGS++))
fi

# Get all pods in namespace
print_section "3. Pod Status Overview"
PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$PODS" -eq 0 ]; then
    print_warn "No pods found in namespace '$NAMESPACE'"
    ((WARNINGS++))
else
    print_success "Found $PODS pod(s) in namespace"
    
    # Count by status (grep -c returns 0 if no matches, which is fine)
    RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
    PENDING=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "Pending" 2>/dev/null || echo "0")
    FAILED=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c -E "Error|CrashLoopBackOff|ImagePullBackOff" 2>/dev/null || echo "0")
    COMPLETED=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "Completed" 2>/dev/null || echo "0")
    
    echo ""
    print_info "Status breakdown:"
    echo "  Running:   $RUNNING"
    echo "  Pending:   $PENDING"
    echo "  Failed:    $FAILED"
    echo "  Completed: $COMPLETED"
    
    if [ "$FAILED" -gt 0 ]; then
        print_error "Some pods are in failed state"
        HEALTHY=false
        ((ERRORS++))
    fi
    
    if [ "$PENDING" -gt 0 ]; then
        print_warn "Some pods are still pending"
        ((WARNINGS++))
    fi
fi

# Detailed pod information
if [ "$DETAILED" = true ]; then
    print_section "3.1. Detailed Pod Status"
    kubectl get pods -n "$NAMESPACE" -o wide
fi

# Resource utilization (CPU and Memory)
if [ "$METRICS_AVAILABLE" = true ]; then
    print_section "4. Resource Utilization (CPU & Memory)"
    
    # Get top pods
    if kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -1 > /dev/null 2>&1; then
        echo ""
        print_subsection "Top Pods by CPU Usage"
        echo ""
        printf "%-50s %10s %10s\n" "POD NAME" "CPU(m)" "MEMORY(Mi)"
        echo "────────────────────────────────────────────────────────────────────────────"
        
        # Get top pods and format output
        kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | while read -r line; do
            POD_NAME=$(echo "$line" | awk '{print $1}')
            CPU=$(echo "$line" | awk '{print $2}')
            MEMORY=$(echo "$line" | awk '{print $3}')
            
            # Show basic metrics (percentage calculation is complex and requires bc/awk)
            printf "%-50s %10s %10s\n" "$POD_NAME" "$CPU" "$MEMORY"
        done
        
        echo ""
        print_subsection "Top Pods by Memory Usage"
        echo ""
        printf "%-50s %10s %10s\n" "POD NAME" "CPU(m)" "MEMORY(Mi)"
        echo "────────────────────────────────────────────────────────────────────────────"
        
        kubectl top pods -n "$NAMESPACE" --no-headers --sort-by=memory 2>/dev/null | head -20 | while read -r line; do
            POD_NAME=$(echo "$line" | awk '{print $1}')
            CPU=$(echo "$line" | awk '{print $2}')
            MEMORY=$(echo "$line" | awk '{print $3}')
            printf "%-50s %10s %10s\n" "$POD_NAME" "$CPU" "$MEMORY"
        done
        
        # Check for high resource usage
        echo ""
        print_subsection "Resource Usage Warnings"
        HIGH_CPU_COUNT=0
        HIGH_MEM_COUNT=0
        
        while IFS= read -r line; do
            POD_NAME=$(echo "$line" | awk '{print $1}')
            CPU=$(echo "$line" | awk '{print $2}')
            MEMORY=$(echo "$line" | awk '{print $3}')
            
            # Check CPU (if > 1000m or > 1 core)
            CPU_M=$(echo "$CPU" | sed 's/m//' | sed 's/^$/0/')
            if [ -n "$CPU_M" ] && [ "$CPU_M" -gt 1000 ] 2>/dev/null; then
                print_warn "High CPU usage: $POD_NAME ($CPU)"
                HIGH_CPU_COUNT=$((HIGH_CPU_COUNT + 1))
            fi
            
            # Check Memory (if > 1Gi = 1024Mi)
            MEM_M=$(echo "$MEMORY" | sed 's/Mi//')
            if [ -n "$MEM_M" ] && [ "$MEM_M" -gt 1024 ] 2>/dev/null; then
                print_warn "High memory usage: $POD_NAME ($MEMORY)"
                HIGH_MEM_COUNT=$((HIGH_MEM_COUNT + 1))
            fi
        done < <(kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null)
        
        if [ "$HIGH_CPU_COUNT" -eq 0 ] && [ "$HIGH_MEM_COUNT" -eq 0 ]; then
            print_success "No pods with unusually high resource usage"
        fi
    else
        print_warn "Could not retrieve pod metrics"
        print_info "This might be because metrics-server is still initializing"
        ((WARNINGS++))
    fi
else
    print_section "4. Resource Utilization"
    print_warn "Skipping resource utilization (metrics-server not available)"
fi

# Node resource usage
if [ "$METRICS_AVAILABLE" = true ]; then
    print_section "5. Node Resource Usage"
    
    if kubectl top nodes --no-headers 2>/dev/null | head -1 > /dev/null 2>&1; then
        echo ""
        printf "%-30s %10s %10s %10s %10s\n" "NODE" "CPU(cores)" "CPU%" "MEMORY(Mi)" "MEM%"
        echo "────────────────────────────────────────────────────────────────────────────"
        kubectl top nodes --no-headers 2>/dev/null | while read -r line; do
            NODE=$(echo "$line" | awk '{print $1}')
            CPU=$(echo "$line" | awk '{print $2}')
            CPU_PCT=$(echo "$line" | awk '{print $3}')
            MEMORY=$(echo "$line" | awk '{print $4}')
            MEM_PCT=$(echo "$line" | awk '{print $5}')
            printf "%-30s %10s %10s %10s %10s\n" "$NODE" "$CPU" "$CPU_PCT" "$MEMORY" "$MEM_PCT"
        done
    else
        print_warn "Could not retrieve node metrics"
    fi
fi

# Service endpoints
print_section "6. Service Endpoints"
SERVICES=$(kubectl get svc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$SERVICES" -eq 0 ]; then
    print_warn "No services found in namespace '$NAMESPACE'"
    ((WARNINGS++))
else
    print_success "Found $SERVICES service(s)"
    echo ""
    
    # Check each service
    while IFS= read -r line; do
        SVC_NAME=$(echo "$line" | awk '{print $1}')
        SVC_TYPE=$(echo "$line" | awk '{print $2}')
        ENDPOINTS=$(kubectl get endpoints "$SVC_NAME" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
        
        # Skip checking endpoints for LoadBalancer services that are pending (external IP not assigned yet)
        # This is normal for GKE LoadBalancers that are still provisioning
        if [ "$ENDPOINTS" -gt 0 ]; then
            print_success "$SVC_NAME ($SVC_TYPE) - $ENDPOINTS endpoint(s)"
        else
            # Check if this is a LoadBalancer that's still provisioning
            EXTERNAL_IP=$(kubectl get svc "$SVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            if [ "$SVC_TYPE" = "LoadBalancer" ] && [ -z "$EXTERNAL_IP" ]; then
                print_info "$SVC_NAME ($SVC_TYPE) - LoadBalancer provisioning (no external IP yet)"
            else
                print_warn "$SVC_NAME ($SVC_TYPE) - No endpoints"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi
    done < <(kubectl get svc -n "$NAMESPACE" --no-headers 2>/dev/null)
fi

# Deployment status
print_section "7. Deployment Status"
DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$DEPLOYMENTS" -eq 0 ]; then
    print_warn "No deployments found in namespace '$NAMESPACE'"
    ((WARNINGS++))
else
    print_success "Found $DEPLOYMENTS deployment(s)"
    echo ""
    
    # Check each deployment
    UNREADY=0
    while IFS= read -r line; do
        DEPLOYMENT=$(echo "$line" | awk '{print $1}')
        READY=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
        DESIRED=$(echo "$line" | awk '{print $2}' | cut -d'/' -f2)
        AVAILABLE=$(echo "$line" | awk '{print $3}')
        
        if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
            print_success "$DEPLOYMENT: $READY/$DESIRED ready"
        else
            print_warn "$DEPLOYMENT: $READY/$DESIRED ready (Available: $AVAILABLE)"
            UNREADY=$((UNREADY + 1))
            WARNINGS=$((WARNINGS + 1))
        fi
    done < <(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null)
    
    if [ "$UNREADY" -gt 0 ]; then
        HEALTHY=false
    fi
fi

# Network metrics (if available via Prometheus or other monitoring)
print_section "8. Network Activity"
# Check if we can get network stats from pods
NETWORK_INFO=false
if kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -1 > /dev/null 2>&1; then
    FIRST_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -1 | awk '{print $1}')
    if [ -n "$FIRST_POD" ]; then
        # Try to get network stats from container runtime (if accessible)
        print_info "Network metrics require Prometheus or container runtime access"
        print_info "For detailed network metrics, check Prometheus/Grafana dashboards"
        NETWORK_INFO=true
    fi
fi

# Summary
print_section "9. Health Summary"
echo ""

if [ "$HEALTHY" = true ] && [ "$ERRORS" -eq 0 ]; then
    print_success "Overall Status: HEALTHY"
    echo ""
    print_info "✓ All critical checks passed"
    print_info "✓ System appears ready for testing"
    if [ "$WARNINGS" -gt 0 ]; then
        print_info "⚠ $WARNINGS warning(s) - review above"
    fi
else
    print_error "Overall Status: UNHEALTHY"
    echo ""
    if [ "$ERRORS" -gt 0 ]; then
        print_error "$ERRORS error(s) detected - fix before testing"
    fi
    if [ "$WARNINGS" -gt 0 ]; then
        print_warn "$WARNINGS warning(s) - review above"
    fi
fi

echo ""
print_info "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Exit code
if [ "$HEALTHY" = true ] && [ "$ERRORS" -eq 0 ]; then
    exit 0
else
    exit 1
fi

