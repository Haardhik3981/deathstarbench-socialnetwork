#!/bin/bash

# Create ConfigMaps by creating a temporary flat structure
# Then kubectl can read it properly

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMaps (Working Method) ==="
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

# Create temporary directories
TEMP_DIR=$(mktemp -d)
API_TEMP="${TEMP_DIR}/api"
WRK2_TEMP="${TEMP_DIR}/wrk2-api"

mkdir -p "${API_TEMP}" "${WRK2_TEMP}"

cd "${LUA_SCRIPTS_DIR}"

# Copy api/ files to temp, preserving structure
if [ -d "api" ]; then
    echo ""
    echo "Preparing api/ files..."
    find api -type f | while read -r file; do
        # Get relative path from api/
        rel_path=$(echo "$file" | sed 's|^api/||')
        # Create directory structure in temp
        mkdir -p "$(dirname "${API_TEMP}/${rel_path}")"
        # Copy file
        cp "$file" "${API_TEMP}/${rel_path}"
    done
    
    API_COUNT=$(find "${API_TEMP}" -type f | wc -l | tr -d ' ')
    echo "  Prepared $API_COUNT files"
    
    # Create ConfigMap from temp directory
    # kubectl will create keys with the file paths (including subdirectories)
    echo "  Creating ConfigMap..."
    cd "${API_TEMP}"
    kubectl create configmap nginx-lua-scripts-api --from-file=.
    echo "✓ Created nginx-lua-scripts-api"
    cd "${LUA_SCRIPTS_DIR}"
fi

# Copy wrk2-api/ files to temp, preserving structure
if [ -d "wrk2-api" ]; then
    echo ""
    echo "Preparing wrk2-api/ files..."
    find wrk2-api -type f | while read -r file; do
        # Get relative path from wrk2-api/
        rel_path=$(echo "$file" | sed 's|^wrk2-api/||')
        # Create directory structure in temp
        mkdir -p "$(dirname "${WRK2_TEMP}/${rel_path}")"
        # Copy file
        cp "$file" "${WRK2_TEMP}/${rel_path}"
    done
    
    WRK2_COUNT=$(find "${WRK2_TEMP}" -type f | wc -l | tr -d ' ')
    echo "  Prepared $WRK2_COUNT files"
    
    # Create ConfigMap from temp directory
    echo "  Creating ConfigMap..."
    cd "${WRK2_TEMP}"
    kubectl create configmap nginx-lua-scripts-wrk2-api --from-file=.
    echo "✓ Created nginx-lua-scripts-wrk2-api"
    cd "${LUA_SCRIPTS_DIR}"
fi

# Cleanup
rm -rf "${TEMP_DIR}"

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMaps..."
sleep 2

# Check data sections
for cm in nginx-lua-scripts-api nginx-lua-scripts-wrk2-api; do
    if kubectl get configmap "$cm" >/dev/null 2>&1; then
        # Check if data section exists and has content
        DATA_CHECK=$(kubectl get configmap "$cm" -o jsonpath='{.data}' 2>/dev/null || echo "{}")
        if [ "$DATA_CHECK" != "{}" ] && [ -n "$DATA_CHECK" ] && [ "$DATA_CHECK" != "null" ]; then
            KEY_COUNT=$(kubectl get configmap "$cm" -o json | jq '.data | keys | length' 2>/dev/null || echo "0")
            echo "✓ $cm has $KEY_COUNT files"
        else
            echo "✗ $cm appears to be empty"
            echo "  Checking YAML:"
            kubectl get configmap "$cm" -o yaml | head -20
        fi
    fi
done

echo ""
echo "Done! Now run: ./scripts/apply-lua-configmap-fix.sh"

