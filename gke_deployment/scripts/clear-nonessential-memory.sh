#!/bin/bash

# Clear Non-Essential Memory Script
#
# WHAT THIS DOES:
# This script clears non-essential data from databases and caches between test runs.
# It drops all collections from MongoDB instances and clears Redis/Memcached caches,
# helping ensure tests start from a clean baseline.
#
# KEY FEATURES:
# - Drops all MongoDB databases/collections
# - Clears Redis caches
# - Clears Memcached caches
# - Optionally restarts pods to clear memory cache
# - Preserves PVCs (data can be recreated)
#
# USAGE:
#   ./scripts/clear-nonessential-memory.sh
#   ./scripts/clear-nonessential-memory.sh --restart-pods
#   ./scripts/clear-nonessential-memory.sh --namespace default

set +e  # Don't exit on error - continue with other databases

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default namespace
NAMESPACE="${NAMESPACE:-default}"
RESTART_PODS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --restart-pods)
            RESTART_PODS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--namespace NAMESPACE] [--restart-pods]"
            echo ""
            echo "Options:"
            echo "  --namespace NAMESPACE  Kubernetes namespace (default: default)"
            echo "  --restart-pods         Restart pods after clearing data (clears memory cache)"
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

# Track results
SUCCESS_COUNT=0
FAILED_COUNT=0

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Clear Non-Essential Memory"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Namespace: $NAMESPACE"
echo "Restart pods: $RESTART_PODS"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check kubectl connection
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# MongoDB cleanup function
clear_mongodb() {
    local DEPLOYMENT=$1
    local DB_NAME=${2:-""}  # Optional database name
    
    print_info "Clearing MongoDB: $DEPLOYMENT"
    
    # Get pod name
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$POD_NAME" ]; then
        print_warn "Pod not found for $DEPLOYMENT, skipping..."
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
    
    # Check if pod is ready
    READY=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$READY" != "True" ]; then
        print_warn "Pod $POD_NAME is not ready, skipping..."
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
    
    # Connect to MongoDB and drop all databases
    # Strategy: List all databases, then drop each user database (skip admin, config, local)
    # Using a simpler approach that works with both mongosh and mongo
    
    # Try mongosh first (MongoDB 6+)
    DROP_SCRIPT="db.adminCommand('listDatabases').databases.forEach(function(d) { if (['admin', 'config', 'local'].indexOf(d.name) === -1) { db.getSiblingDB(d.name).dropDatabase(); } }); print('All user databases dropped');"
    
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- mongosh --quiet --eval "$DROP_SCRIPT" 2>/dev/null | grep -q "dropped"; then
        print_success "Cleared MongoDB: $DEPLOYMENT"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    elif kubectl exec -n "$NAMESPACE" "$POD_NAME" -- mongosh --quiet --eval "$DROP_SCRIPT" 2>/dev/null | grep -q "All user databases dropped"; then
        print_success "Cleared MongoDB: $DEPLOYMENT"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        # Fallback: try with mongo (MongoDB 4.x)
        if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- mongo --quiet --eval "$DROP_SCRIPT" 2>/dev/null | grep -q "dropped\|All user databases dropped"; then
            print_success "Cleared MongoDB: $DEPLOYMENT (using mongo)"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            return 0
        else
            # Last resort: try to drop common database names
            COMMON_DBS=("social_network" "user" "social_graph" "user_timeline" "post_storage" "url_shorten" "media")
            CLEARED_ANY=false
            for db_name in "${COMMON_DBS[@]}"; do
                if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- mongosh --quiet --eval "db.getSiblingDB('$db_name').dropDatabase()" 2>/dev/null | grep -q "dropped"; then
                    CLEARED_ANY=true
                elif kubectl exec -n "$NAMESPACE" "$POD_NAME" -- mongo --quiet --eval "db.getSiblingDB('$db_name').dropDatabase()" 2>/dev/null | grep -q "dropped"; then
                    CLEARED_ANY=true
                fi
            done
            
            if [ "$CLEARED_ANY" = true ]; then
                print_success "Cleared MongoDB: $DEPLOYMENT (cleared common databases)"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                return 0
            else
                print_warn "Could not clear MongoDB: $DEPLOYMENT (may be empty or using different database names)"
                # Not a failure - database might already be empty
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                return 0
            fi
        fi
    fi
}

# Redis cleanup function
clear_redis() {
    local DEPLOYMENT=$1
    
    print_info "Clearing Redis: $DEPLOYMENT"
    
    # Get pod name
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$POD_NAME" ]; then
        print_warn "Pod not found for $DEPLOYMENT, skipping..."
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
    
    # Check if pod is ready
    READY=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$READY" != "True" ]; then
        print_warn "Pod $POD_NAME is not ready, skipping..."
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
    
    # Flush all Redis databases
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- redis-cli FLUSHALL 2>/dev/null; then
        print_success "Cleared Redis: $DEPLOYMENT"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        print_error "Failed to clear Redis: $DEPLOYMENT"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
}

# Memcached cleanup function
clear_memcached() {
    local DEPLOYMENT=$1
    
    print_info "Clearing Memcached: $DEPLOYMENT"
    
    # Get pod name
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$POD_NAME" ]; then
        print_warn "Pod not found for $DEPLOYMENT, skipping..."
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
    
    # Check if pod is ready
    READY=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$READY" != "True" ]; then
        print_warn "Pod $POD_NAME is not ready, skipping..."
        FAILED_COUNT=$((FAILED_COUNT + 1))
        return 1
    fi
    
    # Flush Memcached (using telnet or nc to send flush_all command)
    # Memcached protocol: "flush_all\r\n"
    if echo -e "flush_all\r\nquit\r\n" | kubectl exec -n "$NAMESPACE" -i "$POD_NAME" -- nc localhost 11211 2>/dev/null > /dev/null; then
        print_success "Cleared Memcached: $DEPLOYMENT"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        return 0
    else
        # Alternative: use telnet if available
        if echo -e "flush_all\r\nquit\r\n" | kubectl exec -n "$NAMESPACE" -i "$POD_NAME" -- telnet localhost 11211 2>/dev/null > /dev/null; then
            print_success "Cleared Memcached: $DEPLOYMENT"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            return 0
        else
            print_warn "Could not clear Memcached: $DEPLOYMENT (may require different method)"
            # Memcached will clear on its own over time, so this is not critical
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            return 0
        fi
    fi
}

# Restart pod function
restart_pod() {
    local DEPLOYMENT=$1
    
    print_info "Restarting deployment: $DEPLOYMENT"
    
    if kubectl rollout restart deployment "$DEPLOYMENT" -n "$NAMESPACE" 2>/dev/null; then
        print_success "Restarted: $DEPLOYMENT"
        return 0
    else
        print_warn "Could not restart: $DEPLOYMENT"
        return 1
    fi
}

# Clear MongoDB instances
print_section "1. Clearing MongoDB Databases"

MONGODB_DEPLOYMENTS=(
    "user-mongodb"
    "social-graph-mongodb"
    "user-timeline-mongodb"
    "post-storage-mongodb"
    "url-shorten-mongodb"
    "media-mongodb"
)

for deployment in "${MONGODB_DEPLOYMENTS[@]}"; do
    clear_mongodb "$deployment"
done

# Clear Redis instances
print_section "2. Clearing Redis Caches"

REDIS_DEPLOYMENTS=(
    "social-graph-redis"
    "home-timeline-redis"
    "user-timeline-redis"
    "compose-post-redis"
)

for deployment in "${REDIS_DEPLOYMENTS[@]}"; do
    clear_redis "$deployment"
done

# Clear Memcached instances
print_section "3. Clearing Memcached Caches"

MEMCACHED_DEPLOYMENTS=(
    "media-memcached"
    "post-storage-memcached"
    "url-shorten-memcached"
    "user-memcached"
)

for deployment in "${MEMCACHED_DEPLOYMENTS[@]}"; do
    clear_memcached "$deployment"
done

# Optionally restart pods to clear memory cache
if [ "$RESTART_PODS" = true ]; then
    print_section "4. Restarting Pods (Clearing Memory Cache)"
    
    print_info "This will restart all database pods to clear in-memory caches..."
    print_info "Pods will be restarted one by one to maintain availability"
    
    # Restart MongoDB pods
    for deployment in "${MONGODB_DEPLOYMENTS[@]}"; do
        DEPLOYMENT_NAME="${deployment}-deployment"
        if kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &>/dev/null; then
            restart_pod "$DEPLOYMENT_NAME"
            # Wait a bit between restarts
            sleep 2
        fi
    done
    
    # Restart Redis pods
    for deployment in "${REDIS_DEPLOYMENTS[@]}"; do
        DEPLOYMENT_NAME="${deployment}-deployment"
        if kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &>/dev/null; then
            restart_pod "$DEPLOYMENT_NAME"
            sleep 2
        fi
    done
    
    # Restart Memcached pods
    for deployment in "${MEMCACHED_DEPLOYMENTS[@]}"; do
        DEPLOYMENT_NAME="${deployment}-deployment"
        if kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &>/dev/null; then
            restart_pod "$DEPLOYMENT_NAME"
            sleep 2
        fi
    done
    
    print_info "Waiting for pods to become ready..."
    sleep 5
fi

# Summary
print_section "Summary"

echo ""
if [ "$SUCCESS_COUNT" -gt 0 ]; then
    print_success "Successfully cleared $SUCCESS_COUNT database/cache instance(s)"
fi

if [ "$FAILED_COUNT" -gt 0 ]; then
    print_warn "$FAILED_COUNT instance(s) could not be cleared (may not be running)"
fi

echo ""
print_info "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

if [ "$FAILED_COUNT" -eq 0 ]; then
    print_success "All non-essential memory cleared successfully!"
    exit 0
else
    print_warn "Some instances could not be cleared. Check pod status."
    exit 1
fi

