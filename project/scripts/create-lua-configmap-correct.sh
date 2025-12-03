#!/bin/bash

# CORRECT SOLUTION: Create ConfigMaps by explicitly including each file
# Use the file's relative path (without the parent dir) as the key
# This works because when mounted, the files will be in the right place

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMaps (Correct Method) ==="
echo ""

# Verify source directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "ERROR: Lua scripts directory not found"
    exit 1
fi

# Delete old ConfigMaps
echo "Deleting existing ConfigMaps..."
kubectl delete configmap nginx-lua-scripts-api 2>/dev/null || true
kubectl delete configmap nginx-lua-scripts-wrk2-api 2>/dev/null || true
kubectl delete configmap nginx-lua-scripts 2>/dev/null || true

cd "${LUA_SCRIPTS_DIR}"

# Create ConfigMap for api/ - include ALL files recursively
if [ -d "api" ]; then
    echo ""
    echo "Creating ConfigMap for api/ subdirectory..."
    
    # Find all files in api/ and create ConfigMap with explicit paths
    # Key format: relative path from api/ (e.g., "user/register.lua")
    # This creates keys with slashes, which kubectl handles specially
    API_FILES=$(find api -type f)
    API_COUNT=$(echo "$API_FILES" | grep -v "^$" | wc -l | tr -d ' ')
    
    if [ "$API_COUNT" -gt 0 ]; then
        echo "  Found $API_COUNT files"
        echo "  Creating ConfigMap (this may take a moment)..."
        
        # Build kubectl command - use relative path as key
        KUBECTL_CMD="kubectl create configmap nginx-lua-scripts-api"
        
        for file in $API_FILES; do
            # Key is relative path from api/ (e.g., "user/register.lua")
            # File is the actual file path (e.g., "api/user/register.lua")
            key=$(echo "$file" | sed 's|^api/||')
            KUBECTL_CMD="${KUBECTL_CMD} --from-file=\"${key}\"=\"${file}\""
        done
        
        # Execute - this will fail if keys have slashes, so we need a workaround
        # Actually, let's try creating it via YAML instead
        echo "  Creating via YAML (to handle subdirectories)..."
        
        TEMP_YAML=$(mktemp)
        cat > "$TEMP_YAML" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-lua-scripts-api
data:
EOF
        
        # Add each file to YAML
        for file in $API_FILES; do
            key=$(echo "$file" | sed 's|^api/||')
            # Use literal block scalar to preserve file content
            echo "  ${key}: |" >> "$TEMP_YAML"
            # Indent file content
            sed 's/^/    /' "$file" >> "$TEMP_YAML"
        done
        
        # Apply YAML
        kubectl apply -f "$TEMP_YAML"
        rm -f "$TEMP_YAML"
        
        echo "✓ Created nginx-lua-scripts-api"
    fi
fi

# Create ConfigMap for wrk2-api/ - same approach
if [ -d "wrk2-api" ]; then
    echo ""
    echo "Creating ConfigMap for wrk2-api/ subdirectory..."
    
    WRK2_FILES=$(find wrk2-api -type f)
    WRK2_COUNT=$(echo "$WRK2_FILES" | grep -v "^$" | wc -l | tr -d ' ')
    
    if [ "$WRK2_COUNT" -gt 0 ]; then
        echo "  Found $WRK2_COUNT files"
        echo "  Creating ConfigMap..."
        
        TEMP_YAML=$(mktemp)
        cat > "$TEMP_YAML" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-lua-scripts-wrk2-api
data:
EOF
        
        for file in $WRK2_FILES; do
            key=$(echo "$file" | sed 's|^wrk2-api/||')
            echo "  ${key}: |" >> "$TEMP_YAML"
            sed 's/^/    /' "$file" >> "$TEMP_YAML"
        done
        
        kubectl apply -f "$TEMP_YAML"
        rm -f "$TEMP_YAML"
        
        echo "✓ Created nginx-lua-scripts-wrk2-api"
    fi
fi

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMaps..."
sleep 2

for cm in nginx-lua-scripts-api nginx-lua-scripts-wrk2-api; do
    if kubectl get configmap "$cm" >/dev/null 2>&1; then
        # Check if data section has content
        DATA_KEYS=$(kubectl get configmap "$cm" -o jsonpath='{.data}' 2>/dev/null | grep -o '"[^"]*":' | wc -l | tr -d ' ' || echo "0")
        if [ "$DATA_KEYS" -gt 0 ]; then
            echo "✓ $cm has $DATA_KEYS files"
        else
            echo "✗ $cm appears empty"
            echo "  Checking YAML:"
            kubectl get configmap "$cm" -o yaml | head -30
        fi
    fi
done

echo ""
echo "Done! Now run: ./scripts/apply-lua-configmap-fix.sh"

