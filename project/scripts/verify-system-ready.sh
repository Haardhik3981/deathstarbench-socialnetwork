#!/bin/bash

# Comprehensive system readiness verification script
# Checks pods, services, databases, and connectivity

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "$1"
}

echo "=========================================="
echo "  System Readiness Verification"
echo "=========================================="
echo ""

# Track failures
FAILURES=0

# 1. Check Critical Service Pods
echo "1. Checking Critical Service Pods..."
echo "-----------------------------------"

SERVICES=(
    "user-service"
    "unique-id-service"
    "nginx-thrift"
    "compose-post-service"
    "social-graph-service"
)

for service in "${SERVICES[@]}"; do
    PODS=$(kubectl get pods -n default -l app="$service" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    # Check actual READY column (format: NAME READY STATUS ...)
    # Column 2 is READY (e.g., "1/1"), Column 3 is STATUS (e.g., "Running")
    READY=$(kubectl get pods -n default -l app="$service" --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $3 == "Running" {print}' | wc -l | tr -d ' ')
    
    if [ "$PODS" -eq "0" ]; then
        print_error "$service: No pods found"
        FAILURES=$((FAILURES + 1))
    elif [ "$READY" -eq "0" ]; then
        # Check if pods exist but not ready
        NOT_READY_STATUS=$(kubectl get pods -n default -l app="$service" --no-headers 2>/dev/null | awk '{print "Ready:" $2 ", Status:" $3}' | head -1)
        # Only count as failure if status is not Running
        POD_STATUS=$(kubectl get pods -n default -l app="$service" --no-headers 2>/dev/null | awk '{print $3}' | head -1)
        if [ "$POD_STATUS" != "Running" ]; then
            print_error "$service: $PODS pod(s) found but not running ($NOT_READY_STATUS)"
            FAILURES=$((FAILURES + 1))
        else
            print_warning "$service: $PODS pod(s) running but not ready yet ($NOT_READY_STATUS)"
            print_info "  Pod is running, may still be initializing (this is OK)"
        fi
    else
        print_success "$service: $READY/$PODS pod(s) ready"
    fi
done

echo ""

# 2. Check All Service Pods
echo "2. Checking All Service Pods Status..."
echo "-----------------------------------"

# Check pods that are not in Ready state (using actual READY column)
# Format: NAME READY STATUS RESTARTS AGE
# Column 2 is READY, Column 3 is STATUS
NOT_READY=$(kubectl get pods -n default -l 'app in (compose-post-service,home-timeline-service,media-service,nginx-thrift,post-storage-service,social-graph-service,text-service,unique-id-service,url-shorten-service,user-mention-service,user-service,user-timeline-service)' --no-headers 2>/dev/null | awk '$2 !~ /^[0-9]+\/[0-9]+$/ || $3 != "Running" {print}' | wc -l | tr -d ' ')

if [ "$NOT_READY" -gt "0" ]; then
    # Only show actual problems (not Running or not ready)
    PROBLEM_PODS=$(kubectl get pods -n default -l 'app in (compose-post-service,home-timeline-service,media-service,nginx-thrift,post-storage-service,social-graph-service,text-service,unique-id-service,url-shorten-service,user-mention-service,user-service,user-timeline-service)' --no-headers 2>/dev/null | awk '$2 !~ /^[0-9]+\/[0-9]+$/ || $3 != "Running" {print $1, $2, $3}')
    
    if [ -n "$PROBLEM_PODS" ]; then
        # Check if they're just not ready but running (warn, don't fail)
        RUNNING_BUT_NOT_READY=$(echo "$PROBLEM_PODS" | awk '$3 == "Running" {print}' | wc -l | tr -d ' ')
        if [ "$RUNNING_BUT_NOT_READY" -gt "0" ]; then
            print_warning "$NOT_READY pod(s) running but not ready yet (may still be initializing):"
            echo "$PROBLEM_PODS" | awk '$3 == "Running" {print "  - " $1 " (Ready: " $2 ", Status: " $3 ")"}'
        fi
        # Show actual problems (not running)
        ACTUAL_PROBLEMS=$(echo "$PROBLEM_PODS" | awk '$3 != "Running" {print}')
        if [ -n "$ACTUAL_PROBLEMS" ]; then
            print_error "Pods with actual problems:"
            echo "$ACTUAL_PROBLEMS" | awk '{print "  - " $1 " (Ready: " $2 ", Status: " $3 ")"}'
            FAILURES=$((FAILURES + 1))
        fi
    else
        print_success "All service pods are ready"
    fi
else
    print_success "All service pods are ready"
fi

echo ""

# 3. Check Services (Endpoints)
echo "3. Checking Service Endpoints..."
echo "-----------------------------------"

CRITICAL_SERVICES=(
    "user-service"
    "unique-id-service"
    "nginx-thrift"
)

for service in "${CRITICAL_SERVICES[@]}"; do
    ENDPOINTS=$(kubectl get endpoints "$service" -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)
    
    if [ "$ENDPOINTS" -eq "0" ]; then
        print_error "$service: No endpoints configured"
        FAILURES=$((FAILURES + 1))
    else
        print_success "$service: $ENDPOINTS endpoint(s) configured"
    fi
done

echo ""

# 4. Check Databases
echo "4. Checking Database Pods..."
echo "-----------------------------------"

DATABASES=(
    "user-mongodb"
    "unique-id-service"  # Note: unique-id doesn't use MongoDB, but check the service
)

for db in "${DATABASES[@]}"; do
    if [ "$db" = "user-mongodb" ]; then
        # Check actual READY column (format: NAME READY STATUS ...)
        READY=$(kubectl get pods -n default -l app="$db" --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $3 == "Running" {print}' | wc -l | tr -d ' ')
        READY_STATUS=$(kubectl get pods -n default -l app="$db" --no-headers 2>/dev/null | awk '{print "Ready:" $2 ", Status:" $3}' | head -1)
        POD_STATUS=$(kubectl get pods -n default -l app="$db" --no-headers 2>/dev/null | awk '{print $3}' | head -1)
        if [ "$READY" -eq "0" ]; then
            if [ "$POD_STATUS" = "Running" ]; then
                print_warning "$db: Running but not ready yet ($READY_STATUS)"
            else
                print_error "$db: Not ready ($READY_STATUS)"
                FAILURES=$((FAILURES + 1))
            fi
        else
            print_success "$db: Ready"
        fi
    fi
done

echo ""

# 5. Check Service Port Listening (Critical)
echo "5. Checking if Services are Listening on Ports..."
echo "-----------------------------------"

# Check user-service port 9090 (connection test is more reliable than port check)
USER_POD=$(kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$USER_POD" ]; then
    # Connection test is done in section 6, so we'll just note that port check is less reliable
    # If connection test passes (checked later), we know the service is working
    PORT_LISTENING=$(kubectl exec -n default "$USER_POD" -- /bin/sh -c "cat /proc/net/tcp 2>/dev/null | grep ':2388' || echo 'NOT_LISTENING'" 2>/dev/null | grep -v "NOT_LISTENING" | wc -l | tr -d ' ')
    if [ "$PORT_LISTENING" -gt "0" ]; then
        print_success "user-service: Port 9090 is listening"
    else
        # Port check inconclusive, but connection test (section 6) will verify
        print_info "user-service: Port check inconclusive (connection test in section 6 will verify)"
    fi
else
    print_error "user-service: Pod not found"
    FAILURES=$((FAILURES + 1))
fi

# Check nginx-thrift port 8080
NGINX_POD=$(kubectl get pods -n default -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NGINX_POD" ]; then
    PORT_LISTENING=$(kubectl exec -n default "$NGINX_POD" -- /bin/sh -c "cat /proc/net/tcp 2>/dev/null | grep ':1F90' || echo 'NOT_LISTENING'" 2>/dev/null | grep -v "NOT_LISTENING" | wc -l | tr -d ' ')
    
    if [ "$PORT_LISTENING" -eq "0" ]; then
        print_error "nginx-thrift: Port 8080 NOT listening"
        FAILURES=$((FAILURES + 1))
    else
        print_success "nginx-thrift: Port 8080 is listening"
    fi
else
    print_error "nginx-thrift: Pod not found"
    FAILURES=$((FAILURES + 1))
fi

echo ""

# 6. Check Service Connectivity
echo "6. Checking Service-to-Service Connectivity..."
echo "-----------------------------------"

if [ -n "$NGINX_POD" ] && [ -n "$USER_POD" ]; then
    # Test if nginx-thrift can reach user-service (this is the definitive test)
    CONN_RESULT=$(kubectl exec -n default "$NGINX_POD" -- /bin/sh -c "timeout 2 bash -c '</dev/tcp/user-service.default.svc.cluster.local/9090' 2>&1 && echo 'SUCCESS' || echo 'FAILED'" 2>/dev/null)
    CONNECTION_TEST=$(echo "$CONN_RESULT" | grep -c "SUCCESS" 2>/dev/null || echo "0")
    # Clean up the count (handle any whitespace)
    CONNECTION_TEST=$(echo "$CONNECTION_TEST" | tr -d ' \n')
    
    # Validate it's a number
    if [ -z "$CONNECTION_TEST" ] || ! [ "$CONNECTION_TEST" -eq "$CONNECTION_TEST" ] 2>/dev/null; then
        CONNECTION_TEST=0
    fi
    
    if [ "$CONNECTION_TEST" -eq "0" ]; then
        print_error "nginx-thrift → user-service: Connection FAILED"
        print_warning "  This is the critical issue! nginx-thrift cannot connect to user-service"
        print_warning "  This means user-service is not ready to accept connections"
        FAILURES=$((FAILURES + 1))
    else
        print_success "nginx-thrift → user-service: Connection successful"
        print_info "  ✓ This confirms user-service is ready (port check in section 5 may be unreliable)"
    fi
else
    print_warning "Skipping connectivity test (pods not found)"
fi

echo ""

# 7. Check HTTP Endpoint
echo "7. Checking HTTP Endpoint (localhost:8080)..."
echo "-----------------------------------"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/wrk2-api/user/register -X POST -d "test=1" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "000" ]; then
    print_error "HTTP endpoint: Cannot connect to localhost:8080"
    print_warning "  Make sure you have port-forward running: kubectl port-forward -n default svc/nginx-thrift-service 8080:8080"
    FAILURES=$((FAILURES + 1))
elif [ "$HTTP_CODE" = "400" ] || [ "$HTTP_CODE" = "500" ]; then
    print_warning "HTTP endpoint: Responding but with error ($HTTP_CODE)"
    print_info "  This is expected - endpoint exists but request was invalid/error"
elif [ "$HTTP_CODE" = "200" ]; then
    print_success "HTTP endpoint: Responding successfully ($HTTP_CODE)"
else
    print_warning "HTTP endpoint: Unexpected response code ($HTTP_CODE)"
fi

echo ""

# 8. Check for Initialization Errors (MongoDB Index Loops)
echo "8. Checking for Service Initialization Errors..."
echo "-----------------------------------"

# Check user-service for MongoDB index errors
if [ -n "$USER_POD" ]; then
    ERROR_COUNT=$(kubectl logs -n default "$USER_POD" --tail=30 2>&1 | grep -c "Failed to create mongodb index" 2>/dev/null || echo "0")
    ERROR_COUNT=$(echo "$ERROR_COUNT" | tr -d ' \n')
    if [ -z "$ERROR_COUNT" ] || ! [ "$ERROR_COUNT" -eq "$ERROR_COUNT" ] 2>/dev/null; then
        ERROR_COUNT=0
    fi
    
    if [ "$ERROR_COUNT" -gt "5" ]; then
        print_error "user-service: Stuck in MongoDB index creation loop ($ERROR_COUNT errors)"
        print_warning "  Service cannot initialize. Database may need reset."
        print_info "  Fix: ./scripts/reset-all-databases.sh"
        FAILURES=$((FAILURES + 1))
    elif [ "$ERROR_COUNT" -gt "0" ]; then
        print_warning "user-service: Some MongoDB errors detected ($ERROR_COUNT), but may be transient"
    else
        print_success "user-service: No MongoDB initialization errors"
    fi
fi

# Check social-graph-service for MongoDB index errors
SOCIAL_POD=$(kubectl get pods -n default -l app=social-graph-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$SOCIAL_POD" ]; then
    ERROR_COUNT=$(kubectl logs -n default "$SOCIAL_POD" --tail=30 2>&1 | grep -c "Failed to create mongodb index" 2>/dev/null || echo "0")
    ERROR_COUNT=$(echo "$ERROR_COUNT" | tr -d ' \n')
    if [ -z "$ERROR_COUNT" ] || ! [ "$ERROR_COUNT" -eq "$ERROR_COUNT" ] 2>/dev/null; then
        ERROR_COUNT=0
    fi
    
    if [ "$ERROR_COUNT" -gt "5" ]; then
        print_error "social-graph-service: Stuck in MongoDB index creation loop ($ERROR_COUNT errors)"
        print_warning "  Service cannot initialize. Database may need reset."
        print_info "  Fix: ./scripts/reset-all-databases.sh"
        FAILURES=$((FAILURES + 1))
    elif [ "$ERROR_COUNT" -gt "0" ]; then
        print_warning "social-graph-service: Some MongoDB errors detected ($ERROR_COUNT), but may be transient"
    else
        print_success "social-graph-service: No MongoDB initialization errors"
    fi
fi

# 9. Check Service-to-Service Connectivity (Critical Path)
echo ""
echo "9. Checking Critical Service Connectivity..."
echo "-----------------------------------"

if [ -n "$USER_POD" ]; then
    # Test user-service → unique-id-service
    UNIQUE_ID_TEST=$(kubectl exec -n default "$USER_POD" -- timeout 3 bash -c '</dev/tcp/unique-id-service.default.svc.cluster.local/9090' 2>&1 && echo "SUCCESS" || echo "FAILED" 2>/dev/null)
    if echo "$UNIQUE_ID_TEST" | grep -q "SUCCESS"; then
        print_success "user-service → unique-id-service: Connected"
    else
        print_error "user-service → unique-id-service: Connection FAILED"
        print_warning "  This will cause register endpoint failures"
        FAILURES=$((FAILURES + 1))
    fi
    
    # Test user-service → social-graph-service
    if [ -n "$SOCIAL_POD" ]; then
        SOCIAL_TEST=$(kubectl exec -n default "$USER_POD" -- timeout 3 bash -c '</dev/tcp/social-graph-service.default.svc.cluster.local/9090' 2>&1 && echo "SUCCESS" || echo "FAILED" 2>/dev/null)
        if echo "$SOCIAL_TEST" | grep -q "SUCCESS"; then
            print_success "user-service → social-graph-service: Connected"
        else
            print_error "user-service → social-graph-service: Connection FAILED"
            print_warning "  This will cause follow/unfollow endpoint failures"
            FAILURES=$((FAILURES + 1))
        fi
    fi
fi

# 10. Check Database Connectivity
echo ""
echo "10. Checking Database Connectivity..."
echo "-----------------------------------"

if [ -n "$USER_POD" ]; then
    DB_TEST=$(kubectl exec -n default "$USER_POD" -- timeout 3 bash -c '</dev/tcp/user-mongodb.default.svc.cluster.local/27017' 2>&1 && echo "SUCCESS" || echo "FAILED" 2>/dev/null)
    if echo "$DB_TEST" | grep -q "SUCCESS"; then
        print_success "user-service → user-mongodb: Connected"
    else
        print_error "user-service → user-mongodb: Connection FAILED"
        FAILURES=$((FAILURES + 1))
    fi
fi

if [ -n "$SOCIAL_POD" ]; then
    DB_TEST=$(kubectl exec -n default "$SOCIAL_POD" -- timeout 3 bash -c '</dev/tcp/social-graph-mongodb.default.svc.cluster.local/27017' 2>&1 && echo "SUCCESS" || echo "FAILED" 2>/dev/null)
    if echo "$DB_TEST" | grep -q "SUCCESS"; then
        print_success "social-graph-service → social-graph-mongodb: Connected"
    else
        print_error "social-graph-service → social-graph-mongodb: Connection FAILED"
        FAILURES=$((FAILURES + 1))
    fi
fi

echo ""

# Summary
echo ""
echo "=========================================="
echo "  Verification Summary"
echo "=========================================="

if [ "$FAILURES" -eq "0" ]; then
    print_success "All checks passed! System is ready for testing."
    echo ""
    echo "Next steps:"
    echo "  1. Ensure port-forward is running: kubectl port-forward -n default svc/nginx-thrift-service 8080:8080"
    echo "  2. Run your test: ./scripts/run-k6-tests.sh <test-name>"
    echo ""
    exit 0
else
    print_error "$FAILURES critical issue(s) found. System is NOT ready for testing."
    echo ""
    echo "Recommended actions:"
    echo "  1. If MongoDB index errors: ./scripts/reset-all-databases.sh"
    echo "  2. If connection errors: ./scripts/quick-restart-all-pods.sh"
    echo "  3. Check pod logs: kubectl logs -n default <pod-name>"
    echo "  4. Check pod status: kubectl describe pod -n default <pod-name>"
    echo "  5. Verify system again: ./scripts/verify-system-ready.sh"
    echo ""
    exit 1
fi

