#!/bin/bash

# Fix nginx-thrift port-forward issue by ensuring Lua scripts ConfigMap exists
# and restarting the deployment with the fixed configuration

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"
LUA_SCRIPTS_DIR="${DSB_ROOT}/nginx-web-server/lua-scripts"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

echo ""
print_section "Fixing nginx-thrift Port-Forward Issue"
echo ""

# Step 1: Check if ConfigMap exists
print_section "Step 1: Checking nginx-lua-scripts ConfigMap"
if kubectl get configmap nginx-lua-scripts &>/dev/null; then
    FILE_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null | grep -o '"[^"]*":' | wc -l | tr -d ' ')
    if [ "$FILE_COUNT" -gt 0 ]; then
        print_info "✓ ConfigMap exists with $FILE_COUNT files"
    else
        print_warn "ConfigMap exists but appears empty (0 files)"
        print_info "Deleting empty ConfigMap..."
        kubectl delete configmap nginx-lua-scripts
        RECREATE_CM=true
    fi
else
    print_warn "ConfigMap does not exist"
    RECREATE_CM=true
fi

# Always delete and recreate if we're in recreate mode, to ensure clean state
if [ "$RECREATE_CM" = true ]; then
    # Make sure it's deleted
    kubectl delete configmap nginx-lua-scripts 2>/dev/null || true
fi

# Step 2: Create ConfigMap if needed
if [ "$RECREATE_CM" = true ]; then
    print_section "Step 2: Creating nginx-lua-scripts ConfigMap"
    
    if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
        print_error "Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
        print_error "Please ensure DeathStarBench source is available"
        exit 1
    fi
    
    print_info "Source directory: ${LUA_SCRIPTS_DIR}"
    FILE_COUNT=$(find "${LUA_SCRIPTS_DIR}" -type f | wc -l | tr -d ' ')
    print_info "Found $FILE_COUNT files in source directory"
    
    if [ "$FILE_COUNT" -eq 0 ]; then
        print_error "No files found in Lua scripts directory!"
        exit 1
    fi
    
    # Create ConfigMap by explicitly adding each file with its relative path
    # This method preserves the directory structure (api/, wrk2-api/, etc.)
    print_info "Creating ConfigMap with all files (preserving directory structure)..."
    cd "${LUA_SCRIPTS_DIR}"
    
    # Build kubectl command with all files explicitly
    FILES=$(find . -type f)
    FILE_ARGS=""
    
    for file in $FILES; do
        # Remove leading ./
        clean_path=$(echo "$file" | sed 's|^\./||')
        FILE_ARGS="${FILE_ARGS} --from-file=${clean_path}=${file}"
    done
    
    # Create the ConfigMap with all files
    print_info "Adding $FILE_COUNT files to ConfigMap..."
    kubectl create configmap nginx-lua-scripts $FILE_ARGS
    
    cd "${PROJECT_ROOT}"
    
    # Verify - check if data section exists and has content
    sleep 2
    print_info "Verifying ConfigMap..."
    
    # Try multiple verification methods
    DATA_EXISTS=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null)
    
    if [ -n "$DATA_EXISTS" ] && [ "$DATA_EXISTS" != "{}" ] && [ "$DATA_EXISTS" != "null" ]; then
        # Count keys in the data section
        if command -v python3 &> /dev/null; then
            NEW_COUNT=$(echo "$DATA_EXISTS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")
        else
            # Fallback: count keys manually
            NEW_COUNT=$(echo "$DATA_EXISTS" | grep -o '"[^"]*":' | wc -l | tr -d ' ')
        fi
        
        if [ "$NEW_COUNT" -gt 0 ]; then
            print_info "✓ ConfigMap created with $NEW_COUNT files"
            # Show a few file names as confirmation
            print_info "Sample files in ConfigMap:"
            if command -v python3 &> /dev/null; then
                echo "$DATA_EXISTS" | python3 -c "import sys, json; [print('  -', k) for k in list(json.load(sys.stdin).keys())[:5]]" 2>/dev/null || true
            else
                echo "$DATA_EXISTS" | grep -o '"[^"]*":' | head -5 | sed 's/":$//' | sed 's/^"//' | sed 's/^/  - /'
            fi
        else
            print_warn "ConfigMap created but count is 0, trying alternative method..."
            # Try alternative: use directory method from parent
            kubectl delete configmap nginx-lua-scripts 2>/dev/null
            cd "${LUA_SCRIPTS_DIR}/.."
            kubectl create configmap nginx-lua-scripts --from-file=lua-scripts/
            cd "${PROJECT_ROOT}"
            sleep 2
            ALT_DATA=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' 2>/dev/null)
            if [ -n "$ALT_DATA" ] && [ "$ALT_DATA" != "{}" ]; then
                print_info "✓ Alternative method worked!"
            else
                print_error "Both methods failed. Showing YAML for debugging:"
                kubectl get configmap nginx-lua-scripts -o yaml | head -30
                exit 1
            fi
        fi
    else
        print_error "ConfigMap appears empty. Showing YAML for debugging:"
        kubectl get configmap nginx-lua-scripts -o yaml | head -30
        print_error "ConfigMap creation failed - files may not have been included"
        exit 1
    fi
fi

# Step 3: Apply the updated deployment
print_section "Step 3: Applying updated deployment"
print_info "The deployment has been updated to mount lua-scripts"
print_info "Applying deployment changes..."
kubectl apply -f "${PROJECT_ROOT}/kubernetes/deployments/nginx-thrift-deployment.yaml"

# Step 4: Restart deployment
print_section "Step 4: Restarting nginx-thrift deployment"
print_info "Restarting to pick up the new configuration..."
kubectl rollout restart deployment/nginx-thrift-deployment

# Step 5: Wait for rollout
print_section "Step 5: Waiting for rollout to complete"
print_info "Waiting for nginx-thrift pod to restart..."
kubectl rollout status deployment/nginx-thrift-deployment --timeout=120s || {
    print_warn "Rollout status check timed out, but continuing..."
}

# Step 6: Check pod status
print_section "Step 6: Checking pod status"
sleep 5
NGINX_POD=$(kubectl get pods -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NGINX_POD" ]; then
    print_info "Pod: $NGINX_POD"
    kubectl get pod "$NGINX_POD"
    echo ""
    print_info "Recent logs:"
    kubectl logs "$NGINX_POD" --tail=20 2>&1 | head -20 || print_warn "Could not get logs"
else
    print_warn "Could not find nginx-thrift pod"
fi

echo ""
print_section "Summary"
print_info "✓ Deployment updated with lua-scripts volume mount"
print_info "✓ ConfigMap verified/created"
print_info "✓ Deployment restarted"
echo ""
print_info "Next steps:"
echo "  1. Wait 30-60 seconds for nginx to fully start"
echo "  2. Check pod logs: kubectl logs -l app=nginx-thrift --tail=50"
echo "  3. Try port-forward again: kubectl port-forward svc/nginx-thrift-service 8080:8080"
echo "  4. Or use LoadBalancer IP: kubectl get svc nginx-thrift-service"
echo ""

