#!/bin/bash

# Script to fix MongoDB initialization errors by resetting the database

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "  Fixing MongoDB Initialization Errors"
echo "=========================================="
echo ""
print_warning "This will reset the user-mongodb database (all data will be lost)"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Cancelled."
    exit 1
fi

echo ""

# Step 1: Delete MongoDB pod to reset database
print_info "Step 1: Resetting user-mongodb database..."
kubectl delete pod -n default -l app=user-mongodb 2>/dev/null || print_warning "MongoDB pod not found or already deleted"
echo ""

# Step 2: Wait for MongoDB to restart
print_info "Step 2: Waiting for MongoDB to restart..."
if kubectl wait --for=condition=ready pod -n default -l app=user-mongodb --timeout=120s 2>/dev/null; then
    print_info "✓ MongoDB is ready"
else
    print_error "✗ MongoDB failed to start within 120 seconds"
    print_info "Check status: kubectl get pods -n default -l app=user-mongodb"
    exit 1
fi
echo ""

# Step 3: Restart user-service
print_info "Step 3: Restarting user-service..."
kubectl delete pod -n default -l app=user-service 2>/dev/null || print_warning "user-service pod not found or already deleted"
echo ""

# Step 4: Wait for user-service to initialize
print_info "Step 4: Waiting for user-service to initialize (this may take 30-60 seconds)..."
print_warning "  Service needs to create MongoDB indexes - please be patient"
echo ""

# Wait up to 180 seconds for service to be ready
TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if pod is ready
    READY=$(kubectl get pods -n default -l app=user-service --no-headers 2>/dev/null | grep "Running.*1/1" | wc -l | tr -d ' ')
    
    if [ "$READY" -gt "0" ]; then
        # Check if port is listening
        USER_POD=$(kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$USER_POD" ]; then
            PORT_LISTENING=$(kubectl exec -n default "$USER_POD" -- /bin/sh -c "cat /proc/net/tcp 2>/dev/null | grep ':2388' || echo ''" 2>/dev/null | wc -l | tr -d ' ')
            
            if [ "$PORT_LISTENING" -gt "0" ]; then
                print_info "✓ user-service is ready and listening on port 9090"
                echo ""
                break
            fi
        fi
    fi
    
    # Check for MongoDB errors
    if [ -n "$USER_POD" ]; then
        ERRORS=$(kubectl logs -n default "$USER_POD" --tail=5 2>/dev/null | grep -c "Failed to create mongodb index" || echo "0")
        if [ "$ERRORS" -gt "3" ]; then
            print_error "✗ Still seeing MongoDB errors - database may need more time to reset"
            print_info "  Waiting a bit longer..."
        fi
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done

echo ""
echo ""

if [ $ELAPSED -ge $TIMEOUT ]; then
    print_error "✗ user-service did not become ready within $TIMEOUT seconds"
    print_info "Check logs: kubectl logs -n default -l app=user-service"
    exit 1
fi

# Step 5: Verify service is working
print_info "Step 5: Verifying service connectivity..."

NGINX_POD=$(kubectl get pods -n default -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$NGINX_POD" ] && [ -n "$USER_POD" ]; then
    CONNECTION_TEST=$(kubectl exec -n default "$NGINX_POD" -- /bin/sh -c "timeout 2 bash -c '</dev/tcp/user-service.default.svc.cluster.local/9090' 2>&1 && echo 'SUCCESS' || echo 'FAILED'" 2>/dev/null | grep -c "SUCCESS" || echo "0")
    
    if [ "$CONNECTION_TEST" -gt "0" ]; then
        print_info "✓ nginx-thrift can connect to user-service"
    else
        print_warning "⚠ Connection test failed - service may still be initializing"
    fi
fi

echo ""
echo "=========================================="
print_info "Fix complete!"
echo "=========================================="
echo ""
print_info "Run verification: ./scripts/verify-system-ready.sh"
echo ""

