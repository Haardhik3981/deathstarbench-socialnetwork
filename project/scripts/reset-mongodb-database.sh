#!/bin/bash

# Script to completely reset MongoDB database by deleting PVC
# This will permanently delete all data in the database

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
echo "  Reset MongoDB Database (Complete)"
echo "=========================================="
echo ""
print_warning "⚠️  WARNING: This will PERMANENTLY DELETE all data in user-mongodb!"
print_warning "   This includes all users, posts, and other data."
echo ""

read -p "Are you sure you want to continue? (yes/N): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_info "Cancelled."
    exit 1
fi

echo ""

# Step 1: Scale down MongoDB deployment
print_info "Step 1: Scaling down MongoDB deployment..."
kubectl scale deployment user-mongodb-deployment --replicas=0 -n default
print_info "  Waiting for pod to terminate..."
sleep 5
echo ""

# Step 2: Delete PVC
print_info "Step 2: Deleting persistent volume claim..."
if kubectl delete pvc user-mongodb-pvc -n default 2>/dev/null; then
    print_info "✓ PVC deleted"
else
    print_warning "PVC not found or already deleted"
fi
echo ""

# Step 2.5: Recreate PVC (required for pod to start)
print_info "Step 2.5: Recreating persistent volume claim..."
kubectl apply -f kubernetes/deployments/databases/user-mongodb-deployment.yaml 2>/dev/null || print_warning "Could not apply deployment file (PVC may already exist)"
print_info "  Waiting for PVC to be created..."
sleep 3
echo ""

# Step 3: Scale up MongoDB deployment
print_info "Step 3: Scaling up MongoDB deployment (creating fresh database)..."
kubectl scale deployment user-mongodb-deployment --replicas=1 -n default
echo ""

# Step 4: Wait for MongoDB to be ready
print_info "Step 4: Waiting for MongoDB to be ready..."
if kubectl wait --for=condition=ready pod -n default -l app=user-mongodb --timeout=120s 2>/dev/null; then
    print_info "✓ MongoDB is ready with fresh database"
else
    print_error "✗ MongoDB failed to start within 120 seconds"
    print_info "Check status: kubectl get pods -n default -l app=user-mongodb"
    exit 1
fi
echo ""

# Step 5: Restart user-service
print_info "Step 5: Restarting user-service to initialize with fresh database..."
kubectl delete pod -n default -l app=user-service 2>/dev/null || print_warning "user-service pod not found"
echo ""

# Step 6: Wait for user-service to initialize
print_info "Step 6: Waiting for user-service to initialize (30-60 seconds)..."
print_warning "  Service will create MongoDB indexes on fresh database"
echo ""

TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    READY=$(kubectl get pods -n default -l app=user-service --no-headers 2>/dev/null | grep "Running.*1/1" | wc -l | tr -d ' ')
    
    if [ "$READY" -gt "0" ]; then
        USER_POD=$(kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$USER_POD" ]; then
            # Check if port is listening
            PORT_LISTENING=$(kubectl exec -n default "$USER_POD" -- /bin/sh -c "cat /proc/net/tcp 2>/dev/null | grep ':2388' || echo ''" 2>/dev/null | wc -l | tr -d ' ')
            
            if [ "$PORT_LISTENING" -gt "0" ]; then
                # Check for errors
                ERRORS=$(kubectl logs -n default "$USER_POD" --tail=10 2>/dev/null | grep -c "Failed to create mongodb index" || echo "0")
                if [ "$ERRORS" -eq "0" ]; then
                    print_info "✓ user-service is ready and listening on port 9090"
                    print_info "✓ No MongoDB errors detected"
                    echo ""
                    break
                fi
            fi
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

echo "=========================================="
print_info "✓ Database reset complete!"
echo "=========================================="
echo ""
print_info "Run verification: ./scripts/verify-system-ready.sh"
echo ""

