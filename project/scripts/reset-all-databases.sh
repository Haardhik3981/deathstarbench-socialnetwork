#!/bin/bash

# Comprehensive script to reset ALL MongoDB databases
# This clears stale data and prevents duplicate key errors between tests
# Resets: user-mongodb, social-graph-mongodb, and other MongoDB databases

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
echo "  Reset All MongoDB Databases"
echo "=========================================="
echo ""
print_warning "⚠️  WARNING: This will PERMANENTLY DELETE all data in ALL MongoDB databases!"
print_warning "   This includes:"
print_warning "   - user-mongodb (users, posts)"
print_warning "   - social-graph-mongodb (follow relationships)"
print_warning "   - post-storage-mongodb (post data)"
print_warning "   - user-timeline-mongodb (timeline data)"
print_warning "   - media-mongodb (media metadata)"
print_warning "   - url-shorten-mongodb (URL mappings)"
echo ""

read -p "Are you sure you want to continue? (yes/N): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_info "Cancelled."
    exit 1
fi

echo ""

# Function to clean up stuck MongoDB pods
cleanup_mongodb_pods() {
    local DB_NAME=$1
    
    print_info "  Cleaning up any stuck pods for $DB_NAME..."
    
    # Get all pods for this database
    PODS=$(kubectl get pods -n default -l app="$DB_NAME" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    
    if [ -z "$PODS" ]; then
        return 0
    fi
    
    # Delete pods in problematic states
    for pod in $PODS; do
        STATUS=$(kubectl get pod "$pod" -n default --no-headers 2>/dev/null | awk '{print $3}' || echo "Unknown")
        
        if [[ "$STATUS" == "CrashLoopBackOff" ]] || [[ "$STATUS" == "Error" ]]; then
            print_info "    Deleting stuck pod $pod (status: $STATUS)..."
            kubectl delete pod "$pod" -n default --grace-period=0 --force 2>/dev/null || true
        elif [[ "$STATUS" == "ContainerCreating" ]]; then
            # Check if it's been stuck for more than 2 minutes
            AGE=$(kubectl get pod "$pod" -n default --no-headers 2>/dev/null | awk '{print $5}' || echo "0s")
            AGE_SEC=$(echo "$AGE" | grep -oE '[0-9]+' | head -1 || echo "0")
            AGE_UNIT=$(echo "$AGE" | grep -oE '[a-z]+' | head -1 || echo "s")
            
            # Convert to seconds (rough estimate)
            if [[ "$AGE_UNIT" == "m" ]] && [ "$AGE_SEC" -gt 2 ]; then
                print_info "    Deleting stuck pod $pod (stuck in ContainerCreating for $AGE)..."
                kubectl delete pod "$pod" -n default --grace-period=0 --force 2>/dev/null || true
            fi
        fi
    done
    
    sleep 2
}

# Function to verify no duplicate pods after scale-up
verify_single_pod() {
    local DB_NAME=$1
    local MAX_WAIT=60
    local ELAPSED=0
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        POD_COUNT=$(kubectl get pods -n default -l app="$DB_NAME" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        READY_COUNT=$(kubectl get pods -n default -l app="$DB_NAME" --no-headers 2>/dev/null | grep "Running.*1/1" | wc -l | tr -d ' ')
        
        if [ "$POD_COUNT" -eq "1" ] && [ "$READY_COUNT" -eq "1" ]; then
            return 0
        elif [ "$POD_COUNT" -gt "1" ]; then
            # Delete extra pods (keep the newest one)
            print_warning "    Multiple pods detected, cleaning up duplicates..."
            PODS=$(kubectl get pods -n default -l app="$DB_NAME" --no-headers --sort-by=.metadata.creationTimestamp 2>/dev/null | awk '{print $1}' || echo "")
            FIRST=true
            for pod in $PODS; do
                if [ "$FIRST" = true ]; then
                    FIRST=false
                    continue  # Keep the first (oldest) pod
                fi
                print_info "    Deleting duplicate pod $pod..."
                kubectl delete pod "$pod" -n default --grace-period=0 --force 2>/dev/null || true
            done
            sleep 3
        fi
        
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    
    return 0
}

# Function to reset a MongoDB database
reset_mongodb() {
    local DB_NAME=$1
    local DEPLOYMENT_NAME="${DB_NAME}-deployment"
    local PVC_NAME="${DB_NAME}-pvc"
    local DEPLOYMENT_FILE="kubernetes/deployments/databases/${DEPLOYMENT_NAME}.yaml"
    local SERVICE_NAME="${DB_NAME%-mongodb}"  # Remove -mongodb suffix
    
    print_info "Resetting $DB_NAME..."
    
    # Step 0: Clean up any stuck pods before scaling down
    cleanup_mongodb_pods "$DB_NAME"
    
    # Step 1: Scale down
    if kubectl get deployment "$DEPLOYMENT_NAME" -n default &>/dev/null; then
        print_info "  Scaling down $DEPLOYMENT_NAME..."
        kubectl scale deployment "$DEPLOYMENT_NAME" --replicas=0 -n default 2>/dev/null || true
        sleep 3
        
        # Ensure all pods are terminated
        print_info "  Ensuring all pods are terminated..."
        PODS=$(kubectl get pods -n default -l app="$DB_NAME" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
        for pod in $PODS; do
            if [ -n "$pod" ]; then
                kubectl delete pod "$pod" -n default --grace-period=0 --force 2>/dev/null || true
            fi
        done
        sleep 2
    fi
    
    # Step 2: Delete PVC
    print_info "  Deleting PVC $PVC_NAME..."
    if kubectl delete pvc "$PVC_NAME" -n default 2>/dev/null; then
        print_info "  ✓ PVC deleted"
        sleep 2
    else
        print_warning "  PVC not found (may already be deleted)"
    fi
    
    # Step 3: Recreate PVC from deployment file
    if [ -f "$DEPLOYMENT_FILE" ]; then
        print_info "  Recreating PVC from deployment file..."
        kubectl apply -f "$DEPLOYMENT_FILE" 2>/dev/null || print_warning "  Could not apply (PVC may already exist)"
        sleep 2
    fi
    
    # Step 4: Scale up
    print_info "  Scaling up $DEPLOYMENT_NAME..."
    kubectl scale deployment "$DEPLOYMENT_NAME" --replicas=1 -n default 2>/dev/null || true
    
    # Step 5: Wait for MongoDB to be ready
    print_info "  Waiting for MongoDB to be ready..."
    if kubectl wait --for=condition=ready pod -n default -l app="$DB_NAME" --timeout=120s 2>/dev/null; then
        print_info "  ✓ $DB_NAME is ready"
    else
        print_warning "  MongoDB not ready yet, checking for issues..."
        # Clean up any stuck pods and try again
        cleanup_mongodb_pods "$DB_NAME"
        sleep 5
        if kubectl wait --for=condition=ready pod -n default -l app="$DB_NAME" --timeout=60s 2>/dev/null; then
            print_info "  ✓ $DB_NAME is ready (after cleanup)"
        else
            print_error "  ✗ $DB_NAME failed to start within timeout"
            return 1
        fi
    fi
    
    # Step 5.5: Verify only one pod exists (no duplicates)
    verify_single_pod "$DB_NAME"
    
    # Step 6: Restart associated service (if it exists)
    if [ -n "$SERVICE_NAME" ] && [ "$SERVICE_NAME" != "$DB_NAME" ]; then
        SERVICE_POD=$(kubectl get pods -n default -l app="$SERVICE_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$SERVICE_POD" ]; then
            print_info "  Restarting $SERVICE_NAME to initialize with fresh database..."
            kubectl delete pod -n default -l app="$SERVICE_NAME" 2>/dev/null || true
        fi
    fi
    
    echo ""
    return 0
}

# Reset all MongoDB databases
print_info "Starting database reset process..."
echo ""

# Critical databases (most likely to cause issues)
reset_mongodb "user-mongodb"
reset_mongodb "social-graph-mongodb"

# Other databases
reset_mongodb "post-storage-mongodb"
reset_mongodb "user-timeline-mongodb"
reset_mongodb "media-mongodb"
reset_mongodb "url-shorten-mongodb"

echo ""
print_info "Waiting for services to initialize with fresh databases..."
print_warning "  Services will create MongoDB indexes on fresh databases"
echo ""

# Wait for critical services to be ready
TIMEOUT=180
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check user-service
    USER_READY=$(kubectl get pods -n default -l app=user-service --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $3 == "Running" {print}' | wc -l | tr -d ' ')
    USER_POD=$(kubectl get pods -n default -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    # Check social-graph-service
    SOCIAL_READY=$(kubectl get pods -n default -l app=social-graph-service --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $3 == "Running" {print}' | wc -l | tr -d ' ')
    SOCIAL_POD=$(kubectl get pods -n default -l app=social-graph-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    USER_OK=0
    SOCIAL_OK=0
    
    if [ "$USER_READY" -gt "0" ] && [ -n "$USER_POD" ]; then
        # Check for index errors
        USER_ERRORS=$(kubectl logs -n default "$USER_POD" --tail=10 2>/dev/null | grep -c "Failed to create mongodb index" || echo "0")
        # Clean up the value (remove newlines and whitespace)
        USER_ERRORS=$(echo "$USER_ERRORS" | tr -d ' \n')
        # Validate it's a number
        if [ -z "$USER_ERRORS" ] || ! [ "$USER_ERRORS" -eq "$USER_ERRORS" ] 2>/dev/null; then
            USER_ERRORS=0
        fi
        if [ "$USER_ERRORS" -eq "0" ]; then
            # Test connectivity (with explicit timeout to prevent hanging)
            if timeout 5 kubectl exec -n default "$USER_POD" -- timeout 2 bash -c '</dev/tcp/social-graph-service.default.svc.cluster.local/9090' 2>/dev/null; then
                USER_OK=1
            fi
        fi
    fi
    
    if [ "$SOCIAL_READY" -gt "0" ] && [ -n "$SOCIAL_POD" ]; then
        # Check for index errors
        SOCIAL_ERRORS=$(kubectl logs -n default "$SOCIAL_POD" --tail=10 2>/dev/null | grep -c "Failed to create mongodb index" || echo "0")
        # Clean up the value (remove newlines and whitespace)
        SOCIAL_ERRORS=$(echo "$SOCIAL_ERRORS" | tr -d ' \n')
        # Validate it's a number
        if [ -z "$SOCIAL_ERRORS" ] || ! [ "$SOCIAL_ERRORS" -eq "$SOCIAL_ERRORS" ] 2>/dev/null; then
            SOCIAL_ERRORS=0
        fi
        if [ "$SOCIAL_ERRORS" -eq "0" ]; then
            SOCIAL_OK=1
        fi
    fi
    
    if [ "$USER_OK" -eq "1" ] && [ "$SOCIAL_OK" -eq "1" ]; then
        print_info "✓ Critical services are ready"
        break
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    printf "."
    # Flush output to prevent hanging
    [ -t 1 ] || true
done

# Flush any remaining output and add newline
echo ""
echo ""

if [ $ELAPSED -ge $TIMEOUT ]; then
    print_warning "⚠ Some services may still be initializing"
    print_info "Check status: kubectl get pods -n default"
    print_info "Check logs: kubectl logs -n default -l app=user-service"
    print_info "Check logs: kubectl logs -n default -l app=social-graph-service"
else
    print_info "✓ Critical services initialized successfully"
fi

echo ""
echo "=========================================="
print_info "✓ Database reset complete!"
echo "=========================================="
echo ""
print_info "Next steps:"
print_info "  1. Verify system: ./scripts/verify-system-ready.sh"
print_info "  2. Run tests: ./scripts/run-k6-tests.sh <test-name>"
echo ""

# Explicit exit to ensure clean termination
exit 0
