#!/bin/bash

# Create ConfigMaps with all files from subdirectories
# This properly includes files in nested directories

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMaps (Recursive) ==="
echo ""

# Verify source directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "ERROR: Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

# Delete old ConfigMaps
echo "Deleting existing ConfigMaps..."
kubectl delete configmap nginx-lua-scripts-api 2>/dev/null && echo "  ✓ Deleted nginx-lua-scripts-api" || true
kubectl delete configmap nginx-lua-scripts-wrk2-api 2>/dev/null && echo "  ✓ Deleted nginx-lua-scripts-wrk2-api" || true
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "  ✓ Deleted nginx-lua-scripts" || true

cd "${LUA_SCRIPTS_DIR}"

# Create ConfigMap for api/ subdirectory
# Include all files recursively, using relative paths from api/ as keys
if [ -d "api" ]; then
    echo ""
    echo "Creating ConfigMap for api/ subdirectory..."
    
    API_FILES=$(find api -type f)
    API_COUNT=$(echo "$API_FILES" | grep -v "^$" | wc -l | tr -d ' ')
    echo "  Found $API_COUNT files in api/ subdirectory"
    
    if [ "$API_COUNT" -gt 0 ]; then
        KUBECTL_CMD="kubectl create configmap nginx-lua-scripts-api"
        
        for file in $API_FILES; do
            # Key is the relative path from api/ (e.g., "user/register.lua")
            # File is the full path (e.g., "api/user/register.lua")
            key=$(echo "$file" | sed 's|^api/||')
            KUBECTL_CMD="${KUBECTL_CMD} --from-file=${key}=${file}"
        done
        
        eval "$KUBECTL_CMD"
        echo "✓ Created nginx-lua-scripts-api with $API_COUNT files"
    else
        echo "⚠ No files found in api/"
    fi
fi

# Create ConfigMap for wrk2-api/ subdirectory
if [ -d "wrk2-api" ]; then
    echo ""
    echo "Creating ConfigMap for wrk2-api/ subdirectory..."
    
    WRK2_FILES=$(find wrk2-api -type f)
    WRK2_COUNT=$(echo "$WRK2_FILES" | grep -v "^$" | wc -l | tr -d ' ')
    echo "  Found $WRK2_COUNT files in wrk2-api/ subdirectory"
    
    if [ "$WRK2_COUNT" -gt 0 ]; then
        KUBECTL_CMD="kubectl create configmap nginx-lua-scripts-wrk2-api"
        
        for file in $WRK2_FILES; do
            # Key is the relative path from wrk2-api/ (e.g., "user/register.lua")
            # File is the full path (e.g., "wrk2-api/user/register.lua")
            key=$(echo "$file" | sed 's|^wrk2-api/||')
            KUBECTL_CMD="${KUBECTL_CMD} --from-file=${key}=${file}"
        done
        
        eval "$KUBECTL_CMD"
        echo "✓ Created nginx-lua-scripts-wrk2-api with $WRK2_COUNT files"
    else
        echo "⚠ No files found in wrk2-api/"
    fi
fi

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMaps..."
sleep 2

# Check if ConfigMaps have data
if kubectl get configmap nginx-lua-scripts-api >/dev/null 2>&1; then
    API_DATA=$(kubectl get configmap nginx-lua-scripts-api -o jsonpath='{.data}' 2>/dev/null || echo "{}")
    if [ "$API_DATA" != "{}" ] && [ -n "$API_DATA" ]; then
        API_KEYS=$(echo "$API_DATA" | grep -o '"[^"]*":' | wc -l | tr -d ' ')
        echo "✓ nginx-lua-scripts-api has $API_KEYS files"
    else
        echo "✗ nginx-lua-scripts-api is empty!"
    fi
fi

if kubectl get configmap nginx-lua-scripts-wrk2-api >/dev/null 2>&1; then
    WRK2_DATA=$(kubectl get configmap nginx-lua-scripts-wrk2-api -o jsonpath='{.data}' 2>/dev/null || echo "{}")
    if [ "$WRK2_DATA" != "{}" ] && [ -n "$WRK2_DATA" ]; then
        WRK2_KEYS=$(echo "$WRK2_DATA" | grep -o '"[^"]*":' | wc -l | tr -d ' ')
        echo "✓ nginx-lua-scripts-wrk2-api has $WRK2_KEYS files"
    else
        echo "✗ nginx-lua-scripts-wrk2-api is empty!"
    fi
fi

echo ""
echo "Done! Now run: ./scripts/apply-lua-configmap-fix.sh"

