#!/bin/bash

# Test script to understand how ConfigMaps with subdirectories actually work
# This will help us understand the root cause

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Testing ConfigMap Creation with Subdirectories ==="
echo ""

cd "${LUA_SCRIPTS_DIR}"

# Test 1: Create a test ConfigMap from api/user/ directory
echo "Test 1: Creating ConfigMap from api/user/ (leaf directory)..."
kubectl delete configmap test-lua-user 2>/dev/null || true

cd api/user
kubectl create configmap test-lua-user --from-file=. --dry-run=client -o yaml | head -40
cd "${LUA_SCRIPTS_DIR}"

echo ""
echo "Test 2: What happens with --from-file=api/ (parent with subdirs)?"
kubectl delete configmap test-lua-api 2>/dev/null || true
kubectl create configmap test-lua-api --from-file=api/ --dry-run=client -o yaml | head -40

echo ""
echo "Test 3: Checking if files in api/user/ are actually .lua files..."
ls -la api/user/

echo ""
echo "The key question: Does --from-file=api/ read files in api/user/ subdirectory?"
echo "If not, that's why our ConfigMaps are empty."

