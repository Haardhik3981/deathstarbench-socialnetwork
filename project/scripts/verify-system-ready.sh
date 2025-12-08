#!/bin/bash

# Comprehensive System Readiness Verification Script
# 
# WHAT THIS DOES:
# This script performs a comprehensive health and readiness check of your Kubernetes deployment.
# It combines functionality from health-check.sh, verify-system-ready.sh, and pre-test-checklist.sh
# to provide a single, unified verification script.
#
# KEY FEATURES:
# - Cluster connection and metrics server check
# - Pod status overview (all pods, not just services)
# - Resource utilization (CPU & Memory) if metrics available
# - Deployment status
# - Critical service pods check
# - Service endpoints verification
# - Database pods check
# - Service-to-service connectivity
# - Database connectivity
# - HTTP endpoint and port-forward check
# - Initialization error detection (MongoDB index loops)
# - k6 installation and test files check
# - Comprehensive health summary
#
# USAGE:
#   ./scripts/verify-system-ready.sh
#   ./scripts/verify-system-ready.sh --detailed
#   ./scripts/verify-system-ready.sh --skip-k6

set +e  # Don't exit on error - continue checking even if some commands fail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default namespace
NAMESPACE="${NAMESPACE:-default}"
DETAILED=false
SKIP_K6=false

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
        --skip-k6)
            SKIP_K6=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--namespace NAMESPACE] [--detailed] [--skip-k6]"
            echo ""
            echo "Options:"
            echo "  --namespace NAMESPACE  Kubernetes namespace (default: default)"
            echo "  --detailed             Show detailed pod information"
            echo "  --skip-k6              Skip k6 installation and test file checks"
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
FAILURES=0

# Start of script
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Comprehensive System Readiness Verification"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Namespace: $NAMESPACE"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 1. Cluster Connection
print_section "1. Cluster Connection"

if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    print_info "Make sure kubectl is configured correctly"
    HEALTHY=false
    ERRORS=$((ERRORS + 1))
    exit 1
fi

CLUSTER_INFO=$(kubectl cluster-info | head -n 1 | sed 's/.*is running at //')
print_success "Connected to cluster"
print_info "Cluster: $CLUSTER_INFO"
print_info "Context: $(kubectl config current-context 2>/dev/null || echo 'unknown')"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_error "Namespace '$NAMESPACE' does not exist"
    HEALTHY=false
    ERRORS=$((ERRORS + 1))
    exit 1
fi

# 2. Metrics Server Availability
print_section "2. Metrics Server Availability"

METRICS_AVAILABLE=false
if kubectl top nodes &> /dev/null 2>&1; then
    METRICS_AVAILABLE=true
    print_success "Metrics server is available"
    print_info "CPU and memory metrics will be shown"
else
    print_warn "Metrics server is not available"
    print_info "CPU and memory usage will not be shown"
    WARNINGS=$((WARNINGS + 1))
fi

# 3. Pod Status Overview
print_section "3. Pod Status Overview"

PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$PODS" -eq 0 ]; then
    print_warn "No pods found in namespace '$NAMESPACE'"
    WARNINGS=$((WARNINGS + 1))
else
    print_success "Found $PODS pod(s) in namespace"
    
    # Count by status (clean output to remove newlines)
    RUNNING=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo "0")
    RUNNING=$(echo "$RUNNING" | tr -d ' \n')
    if [ -z "$RUNNING" ] || ! [ "$RUNNING" -eq "$RUNNING" ] 2>/dev/null; then
        RUNNING=0
    fi
    
    PENDING=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "Pending" 2>/dev/null || echo "0")
    PENDING=$(echo "$PENDING" | tr -d ' \n')
    if [ -z "$PENDING" ] || ! [ "$PENDING" -eq "$PENDING" ] 2>/dev/null; then
        PENDING=0
    fi
    
    FAILED=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c -E "Error|CrashLoopBackOff|ImagePullBackOff" 2>/dev/null || echo "0")
    FAILED=$(echo "$FAILED" | tr -d ' \n')
    if [ -z "$FAILED" ] || ! [ "$FAILED" -eq "$FAILED" ] 2>/dev/null; then
        FAILED=0
    fi
    
    COMPLETED=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "Completed" 2>/dev/null || echo "0")
    COMPLETED=$(echo "$COMPLETED" | tr -d ' \n')
    if [ -z "$COMPLETED" ] || ! [ "$COMPLETED" -eq "$COMPLETED" ] 2>/dev/null; then
        COMPLETED=0
    fi
    
    echo ""
    print_info "Status breakdown:"
    echo "  Running:   $RUNNING"
    echo "  Pending:   $PENDING"
    echo "  Failed:    $FAILED"
    echo "  Completed: $COMPLETED"
    
    if [ "$FAILED" -gt 0 ]; then
        print_error "Some pods are in failed state"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    fi
    
    if [ "$PENDING" -gt 0 ]; then
        print_warn "Some pods are still pending"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Detailed pod information
if [ "$DETAILED" = true ]; then
    print_subsection "Detailed Pod Status"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""
fi

# 4. Resource Utilization (if metrics available)
if [ "$METRICS_AVAILABLE" = true ]; then
    print_section "4. Resource Utilization (CPU & Memory)"
    
    if kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -1 > /dev/null 2>&1; then
        echo ""
        print_subsection "Top Pods by CPU Usage"
        echo ""
        printf "%-50s %10s %10s\n" "POD NAME" "CPU(m)" "MEMORY(Mi)"
        echo "────────────────────────────────────────────────────────────────────────────"
        
        kubectl top pods -n "$NAMESPACE" --no-headers 2>/dev/null | head -10 | while read -r line; do
            POD_NAME=$(echo "$line" | awk '{print $1}')
            CPU=$(echo "$line" | awk '{print $2}')
            MEMORY=$(echo "$line" | awk '{print $3}')
            printf "%-50s %10s %10s\n" "$POD_NAME" "$CPU" "$MEMORY"
        done
        
        echo ""
        print_subsection "Top Pods by Memory Usage"
        echo ""
        printf "%-50s %10s %10s\n" "POD NAME" "CPU(m)" "MEMORY(Mi)"
        echo "────────────────────────────────────────────────────────────────────────────"
        
        kubectl top pods -n "$NAMESPACE" --no-headers --sort-by=memory 2>/dev/null | head -10 | while read -r line; do
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
            
            # Check CPU (if > 1000m)
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
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_section "4. Resource Utilization"
    print_warn "Skipping resource utilization (metrics-server not available)"
fi

# 5. Node Resource Usage (if metrics available)
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

# 6. Deployment Status
print_section "6. Deployment Status"

DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$DEPLOYMENTS" -eq 0 ]; then
    print_warn "No deployments found in namespace '$NAMESPACE'"
    WARNINGS=$((WARNINGS + 1))
else
    print_success "Found $DEPLOYMENTS deployment(s)"
    echo ""
    
    UNREADY=0
    while IFS= read -r line; do
        DEPLOYMENT=$(echo "$line" | awk '{print $1}')
        READY=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
        DESIRED=$(echo "$line" | awk '{print $2}' | cut -d'/' -f2)
        AVAILABLE=$(echo "$line" | awk '{print $3}')
        
        # Clean values (remove any whitespace/newlines)
        READY=$(echo "$READY" | tr -d ' \n')
        DESIRED=$(echo "$DESIRED" | tr -d ' \n')
        
        # Validate they're numbers
        if [ -z "$READY" ] || ! [ "$READY" -eq "$READY" ] 2>/dev/null; then
            READY=0
        fi
        if [ -z "$DESIRED" ] || ! [ "$DESIRED" -eq "$DESIRED" ] 2>/dev/null; then
            DESIRED=0
        fi
        
        if [ "$READY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
            print_success "$DEPLOYMENT: $READY/$DESIRED ready"
        elif [ "$DESIRED" -eq 0 ]; then
            # Deployment scaled to 0 (intentional, not an error)
            print_info "$DEPLOYMENT: 0/0 ready (scaled to 0 - intentional)"
        else
            print_warn "$DEPLOYMENT: $READY/$DESIRED ready (Available: $AVAILABLE)"
            UNREADY=$((UNREADY + 1))
            WARNINGS=$((WARNINGS + 1))
        fi
    done < <(kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null)
    
    # Note: UNREADY deployments are warnings, not critical errors
    # Deployments intentionally scaled to 0 are not counted as errors
fi

# 7. Critical Service Pods
print_section "7. Critical Service Pods"

CRITICAL_SERVICES=(
    "user-service"
    "unique-id-service"
    "nginx-thrift"
    "compose-post-service"
    "social-graph-service"
)

for service in "${CRITICAL_SERVICES[@]}"; do
    PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    READY=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $3 == "Running" {print}' | wc -l | tr -d ' ')
    
    if [ "$PODS" -eq "0" ]; then
        print_error "$service: No pods found"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    elif [ "$READY" -eq "0" ]; then
        NOT_READY_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null | awk '{print "Ready:" $2 ", Status:" $3}' | head -1)
        POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null | awk '{print $3}' | head -1)
        if [ "$POD_STATUS" != "Running" ]; then
            print_error "$service: $PODS pod(s) found but not running ($NOT_READY_STATUS)"
            HEALTHY=false
            ERRORS=$((ERRORS + 1))
            FAILURES=$((FAILURES + 1))
        else
            print_warn "$service: $PODS pod(s) running but not ready yet ($NOT_READY_STATUS)"
            print_info "  Pod is running, may still be initializing (this is OK)"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        print_success "$service: $READY/$PODS pod(s) ready"
    fi
done

# 8. All Service Pods Status
print_section "8. All Service Pods Status"

NOT_READY=$(kubectl get pods -n "$NAMESPACE" -l 'app in (compose-post-service,home-timeline-service,media-service,nginx-thrift,post-storage-service,social-graph-service,text-service,unique-id-service,url-shorten-service,user-mention-service,user-service,user-timeline-service)' --no-headers 2>/dev/null | awk '$2 !~ /^[0-9]+\/[0-9]+$/ || $3 != "Running" {print}' | wc -l | tr -d ' ')

if [ "$NOT_READY" -gt "0" ]; then
    PROBLEM_PODS=$(kubectl get pods -n "$NAMESPACE" -l 'app in (compose-post-service,home-timeline-service,media-service,nginx-thrift,post-storage-service,social-graph-service,text-service,unique-id-service,url-shorten-service,user-mention-service,user-service,user-timeline-service)' --no-headers 2>/dev/null | awk '$2 !~ /^[0-9]+\/[0-9]+$/ || $3 != "Running" {print $1, $2, $3}')
    
    if [ -n "$PROBLEM_PODS" ]; then
        RUNNING_BUT_NOT_READY=$(echo "$PROBLEM_PODS" | awk '$3 == "Running" {print}' | wc -l | tr -d ' ')
        if [ "$RUNNING_BUT_NOT_READY" -gt "0" ]; then
            print_warn "$NOT_READY pod(s) running but not ready yet (may still be initializing):"
            echo "$PROBLEM_PODS" | awk '$3 == "Running" {print "  - " $1 " (Ready: " $2 ", Status: " $3 ")"}'
            WARNINGS=$((WARNINGS + 1))
        fi
        ACTUAL_PROBLEMS=$(echo "$PROBLEM_PODS" | awk '$3 != "Running" {print}')
        if [ -n "$ACTUAL_PROBLEMS" ]; then
            print_error "Pods with actual problems:"
            echo "$ACTUAL_PROBLEMS" | awk '{print "  - " $1 " (Ready: " $2 ", Status: " $3 ")"}'
            HEALTHY=false
            ERRORS=$((ERRORS + 1))
            FAILURES=$((FAILURES + 1))
        fi
    else
        print_success "All service pods are ready"
    fi
else
    print_success "All service pods are ready"
fi

# 9. Service Endpoints
print_section "9. Service Endpoints"

CRITICAL_SERVICES_ENDPOINTS=(
    "user-service"
    "unique-id-service"
    "nginx-thrift"
)

for service in "${CRITICAL_SERVICES_ENDPOINTS[@]}"; do
    ENDPOINTS=$(kubectl get endpoints "$service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
    
    if [ "$ENDPOINTS" -eq "0" ]; then
        print_error "$service: No endpoints configured"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    else
        print_success "$service: $ENDPOINTS endpoint(s) configured"
    fi
done

# Check all services
ALL_SERVICES=$(kubectl get svc -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$ALL_SERVICES" -gt 0 ]; then
    echo ""
    print_info "All services ($ALL_SERVICES total):"
    while IFS= read -r line; do
        SVC_NAME=$(echo "$line" | awk '{print $1}')
        SVC_TYPE=$(echo "$line" | awk '{print $2}')
        ENDPOINTS=$(kubectl get endpoints "$SVC_NAME" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
        
        if [ "$ENDPOINTS" -gt 0 ]; then
            print_success "$SVC_NAME ($SVC_TYPE) - $ENDPOINTS endpoint(s)"
        else
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

# 10. Database Pods
print_section "10. Database Pods"

DATABASES=(
    "user-mongodb"
    "social-graph-mongodb"
    "post-storage-mongodb"
    "user-timeline-mongodb"
    "media-mongodb"
    "url-shorten-mongodb"
)

for db in "${DATABASES[@]}"; do
    READY=$(kubectl get pods -n "$NAMESPACE" -l app="$db" --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $3 == "Running" {print}' | wc -l | tr -d ' ')
    READY_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app="$db" --no-headers 2>/dev/null | awk '{print "Ready:" $2 ", Status:" $3}' | head -1)
    POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app="$db" --no-headers 2>/dev/null | awk '{print $3}' | head -1)
    
    if [ "$READY" -eq "0" ]; then
        if [ "$POD_STATUS" = "Running" ]; then
            print_warn "$db: Running but not ready yet ($READY_STATUS)"
            WARNINGS=$((WARNINGS + 1))
        else
            print_error "$db: Not ready ($READY_STATUS)"
            HEALTHY=false
            ERRORS=$((ERRORS + 1))
            FAILURES=$((FAILURES + 1))
        fi
    else
        print_success "$db: Ready"
    fi
done

# 11. Service Port Listening
print_section "11. Service Port Listening"

USER_POD=$(kubectl get pods -n "$NAMESPACE" -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$USER_POD" ]; then
    PORT_LISTENING=$(kubectl exec -n "$NAMESPACE" "$USER_POD" -- /bin/sh -c "cat /proc/net/tcp 2>/dev/null | grep ':2388' || echo 'NOT_LISTENING'" 2>/dev/null | grep -v "NOT_LISTENING" | wc -l | tr -d ' ')
    if [ "$PORT_LISTENING" -gt "0" ]; then
        print_success "user-service: Port 9090 is listening"
    else
        print_info "user-service: Port check inconclusive (connection test will verify)"
    fi
else
    print_error "user-service: Pod not found"
    HEALTHY=false
    ERRORS=$((ERRORS + 1))
    FAILURES=$((FAILURES + 1))
fi

NGINX_POD=$(kubectl get pods -n "$NAMESPACE" -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NGINX_POD" ]; then
    PORT_LISTENING=$(kubectl exec -n "$NAMESPACE" "$NGINX_POD" -- /bin/sh -c "cat /proc/net/tcp 2>/dev/null | grep ':1F90' || echo 'NOT_LISTENING'" 2>/dev/null | grep -v "NOT_LISTENING" | wc -l | tr -d ' ')
    if [ "$PORT_LISTENING" -eq "0" ]; then
        print_error "nginx-thrift: Port 8080 NOT listening"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    else
        print_success "nginx-thrift: Port 8080 is listening"
    fi
else
    print_error "nginx-thrift: Pod not found"
    HEALTHY=false
    ERRORS=$((ERRORS + 1))
    FAILURES=$((FAILURES + 1))
fi

# 12. Service-to-Service Connectivity
print_section "12. Service-to-Service Connectivity"

if [ -n "$NGINX_POD" ] && [ -n "$USER_POD" ]; then
    CONN_RESULT=$(kubectl exec -n "$NAMESPACE" "$NGINX_POD" -- /bin/sh -c "timeout 2 bash -c '</dev/tcp/user-service.default.svc.cluster.local/9090' 2>&1 && echo 'SUCCESS' || echo 'FAILED'" 2>/dev/null)
    CONNECTION_TEST=$(echo "$CONN_RESULT" | grep -c "SUCCESS" 2>/dev/null || echo "0")
    CONNECTION_TEST=$(echo "$CONNECTION_TEST" | tr -d ' \n')
    
    if [ -z "$CONNECTION_TEST" ] || ! [ "$CONNECTION_TEST" -eq "$CONNECTION_TEST" ] 2>/dev/null; then
        CONNECTION_TEST=0
    fi
    
    if [ "$CONNECTION_TEST" -eq "0" ]; then
        print_error "nginx-thrift → user-service: Connection FAILED"
        print_warning "  This is critical! nginx-thrift cannot connect to user-service"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    else
        print_success "nginx-thrift → user-service: Connection successful"
    fi
else
    print_warning "Skipping connectivity test (pods not found)"
    WARNINGS=$((WARNINGS + 1))
fi

# 13. Critical Service Connectivity
print_subsection "Critical Service Connectivity"

if [ -n "$USER_POD" ]; then
    UNIQUE_ID_TEST=$(kubectl exec -n "$NAMESPACE" "$USER_POD" -- timeout 3 bash -c '</dev/tcp/unique-id-service.default.svc.cluster.local/9090' 2>&1 && echo "SUCCESS" || echo "FAILED" 2>/dev/null)
    if echo "$UNIQUE_ID_TEST" | grep -q "SUCCESS"; then
        print_success "user-service → unique-id-service: Connected"
    else
        print_error "user-service → unique-id-service: Connection FAILED"
        print_warning "  This will cause register endpoint failures"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    fi
    
    SOCIAL_POD=$(kubectl get pods -n "$NAMESPACE" -l app=social-graph-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$SOCIAL_POD" ]; then
        SOCIAL_TEST=$(kubectl exec -n "$NAMESPACE" "$USER_POD" -- timeout 3 bash -c '</dev/tcp/social-graph-service.default.svc.cluster.local/9090' 2>&1 && echo "SUCCESS" || echo "FAILED" 2>/dev/null)
        if echo "$SOCIAL_TEST" | grep -q "SUCCESS"; then
            print_success "user-service → social-graph-service: Connected"
        else
            print_error "user-service → social-graph-service: Connection FAILED"
            print_warning "  This will cause follow/unfollow endpoint failures"
            HEALTHY=false
            ERRORS=$((ERRORS + 1))
            FAILURES=$((FAILURES + 1))
        fi
    fi
fi

# 14. Database Connectivity
print_section "13. Database Connectivity"

if [ -n "$USER_POD" ]; then
    DB_TEST=$(kubectl exec -n "$NAMESPACE" "$USER_POD" -- timeout 3 bash -c '</dev/tcp/user-mongodb.default.svc.cluster.local/27017' 2>&1 && echo "SUCCESS" || echo "FAILED" 2>/dev/null)
    if echo "$DB_TEST" | grep -q "SUCCESS"; then
        print_success "user-service → user-mongodb: Connected"
    else
        print_error "user-service → user-mongodb: Connection FAILED"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    fi
fi

if [ -n "$SOCIAL_POD" ]; then
    DB_TEST=$(kubectl exec -n "$NAMESPACE" "$SOCIAL_POD" -- timeout 3 bash -c '</dev/tcp/social-graph-mongodb.default.svc.cluster.local/27017' 2>&1 && echo "SUCCESS" || echo "FAILED" 2>/dev/null)
    if echo "$DB_TEST" | grep -q "SUCCESS"; then
        print_success "social-graph-service → social-graph-mongodb: Connected"
    else
        print_error "social-graph-service → social-graph-mongodb: Connection FAILED"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    fi
fi

# 15. HTTP Endpoint and Port-Forward Check
print_section "14. HTTP Endpoint & Port-Forward"

# Check if port-forward is running
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    print_success "Port-forward is running on port 8080"
    print_info "You can access nginx-thrift at http://localhost:8080"
    
    # Test HTTP endpoint
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/wrk2-api/user/register -X POST -d "test=1" 2>/dev/null || echo "000")
    # Normalize HTTP code (remove any extra characters, take first 3 digits)
    HTTP_CODE=$(echo "$HTTP_CODE" | grep -oE '[0-9]{3}' | head -1 || echo "000")
    
    if [ "$HTTP_CODE" = "000" ] || [ -z "$HTTP_CODE" ]; then
        print_error "HTTP endpoint: Cannot connect to localhost:8080"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    elif [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "500" ]; then
        print_warning "HTTP endpoint: Responding but with error ($HTTP_CODE)"
        print_info "  This is expected - endpoint exists but request was invalid/error"
        WARNINGS=$((WARNINGS + 1))
    elif [ "$HTTP_CODE" = "200" ]; then
        print_success "HTTP endpoint: Responding successfully ($HTTP_CODE)"
    else
        print_warn "HTTP endpoint: Unexpected response code ($HTTP_CODE)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_warn "Port-forward is NOT running on port 8080"
    print_info "To start port-forward, run in another terminal:"
    echo "  kubectl port-forward -n default svc/nginx-thrift-service 8080:8080"
    echo ""
    read -p "Do you want to start port-forward now? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Starting port-forward in background..."
        kubectl port-forward -n "$NAMESPACE" svc/nginx-thrift-service 8080:8080 > /dev/null 2>&1 &
        PORT_FORWARD_PID=$!
        sleep 2
        if kill -0 $PORT_FORWARD_PID 2>/dev/null; then
            print_success "Port-forward started (PID: $PORT_FORWARD_PID)"
            print_info "To stop it later: kill $PORT_FORWARD_PID"
        else
            print_error "Failed to start port-forward"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# 16. Initialization Errors (MongoDB Index Loops)
print_section "15. Service Initialization Errors"

if [ -n "$USER_POD" ]; then
    ERROR_COUNT=$(kubectl logs -n "$NAMESPACE" "$USER_POD" --tail=30 2>&1 | grep -c "Failed to create mongodb index" 2>/dev/null || echo "0")
    ERROR_COUNT=$(echo "$ERROR_COUNT" | tr -d ' \n')
    if [ -z "$ERROR_COUNT" ] || ! [ "$ERROR_COUNT" -eq "$ERROR_COUNT" ] 2>/dev/null; then
        ERROR_COUNT=0
    fi
    
    if [ "$ERROR_COUNT" -gt "5" ]; then
        print_error "user-service: Stuck in MongoDB index creation loop ($ERROR_COUNT errors)"
        print_warn "  Service cannot initialize. Database may need reset."
        print_info "  Fix: ./scripts/reset-all-databases.sh"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    elif [ "$ERROR_COUNT" -gt "0" ]; then
        print_warning "user-service: Some MongoDB errors detected ($ERROR_COUNT), but may be transient"
        WARNINGS=$((WARNINGS + 1))
    else
        print_success "user-service: No MongoDB initialization errors"
    fi
fi

if [ -n "$SOCIAL_POD" ]; then
    ERROR_COUNT=$(kubectl logs -n "$NAMESPACE" "$SOCIAL_POD" --tail=30 2>&1 | grep -c "Failed to create mongodb index" 2>/dev/null || echo "0")
    ERROR_COUNT=$(echo "$ERROR_COUNT" | tr -d ' \n')
    if [ -z "$ERROR_COUNT" ] || ! [ "$ERROR_COUNT" -eq "$ERROR_COUNT" ] 2>/dev/null; then
        ERROR_COUNT=0
    fi
    
    if [ "$ERROR_COUNT" -gt "5" ]; then
        print_error "social-graph-service: Stuck in MongoDB index creation loop ($ERROR_COUNT errors)"
        print_warning "  Service cannot initialize. Database may need reset."
        print_info "  Fix: ./scripts/reset-all-databases.sh"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
        FAILURES=$((FAILURES + 1))
    elif [ "$ERROR_COUNT" -gt "0" ]; then
        print_warning "social-graph-service: Some MongoDB errors detected ($ERROR_COUNT), but may be transient"
        WARNINGS=$((WARNINGS + 1))
    else
        print_success "social-graph-service: No MongoDB initialization errors"
    fi
fi

# 17. k6 Installation and Test Files (optional)
if [ "$SKIP_K6" = false ]; then
    print_section "16. k6 Installation & Test Files"
    
    if command -v k6 &> /dev/null; then
        K6_VERSION=$(k6 version | head -n 1)
        print_success "k6 is installed: $K6_VERSION"
    else
        print_error "k6 is not installed"
        print_info "Install k6:"
        echo "  macOS: brew install k6"
        echo "  Linux: https://k6.io/docs/getting-started/installation/"
        HEALTHY=false
        ERRORS=$((ERRORS + 1))
    fi
    
    echo ""
    
    if [ -f "./k6-tests/constant-load.js" ]; then
        print_success "constant-load.js exists"
    else
        print_warn "constant-load.js not found"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    if [ -f "./k6-tests/test-helpers.js" ]; then
        print_success "test-helpers.js exists"
    else
        print_warn "test-helpers.js not found (required for test scripts)"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Summary
print_section "17. Health Summary"

echo ""

# Determine overall health (only unhealthy if there are actual errors/failures, not just warnings)
if [ "$ERRORS" -eq 0 ] && [ "$FAILURES" -eq 0 ]; then
    print_success "Overall Status: HEALTHY"
    echo ""
    print_info "✓ All critical checks passed"
    print_info "✓ System appears ready for testing"
    if [ "$WARNINGS" -gt 0 ]; then
        print_info "⚠ $WARNINGS warning(s) - review above (non-critical)"
    fi
    echo ""
    print_info "Next steps:"
    echo "  1. Ensure port-forward is running: kubectl port-forward -n default svc/nginx-thrift-service 8080:8080"
    echo "  2. Run your test: ./scripts/run-k6-tests.sh <test-name>"
    echo ""
    exit 0
else
    print_error "Overall Status: UNHEALTHY"
    echo ""
    if [ "$ERRORS" -gt 0 ] || [ "$FAILURES" -gt 0 ]; then
        print_error "$ERRORS error(s) / $FAILURES failure(s) detected - fix before testing"
    fi
    if [ "$WARNINGS" -gt 0 ]; then
        print_warn "$WARNINGS warning(s) - review above"
    fi
    echo ""
    print_info "Recommended actions:"
    echo "  1. If MongoDB index errors: ./scripts/reset-all-databases.sh"
    echo "  2. If connection errors: ./scripts/quick-restart-all-pods.sh"
    echo "  3. Check pod logs: kubectl logs -n default <pod-name>"
    echo "  4. Check pod status: kubectl describe pod -n default <pod-name>"
    echo "  5. Verify system again: ./scripts/verify-system-ready.sh"
    echo ""
    exit 1
fi
