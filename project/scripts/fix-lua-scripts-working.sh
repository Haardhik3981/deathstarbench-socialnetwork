#!/bin/bash

# Fix nginx-lua-scripts ConfigMap by explicitly including subdirectories

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Fixing nginx-lua-scripts ConfigMap ===${NC}"
echo ""

# Delete old ConfigMap
echo "Deleting old ConfigMap..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "✓ Deleted" || echo "Didn't exist"

echo ""
echo "Creating ConfigMap by explicitly including api and wrk2-api subdirectories..."

# Create ConfigMap with explicit subdirectories
cd "${LUA_SCRIPTS_DIR}"

kubectl create configmap nginx-lua-scripts \
  --from-file=api \
  --from-file=wrk2-api

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMap..."
sleep 2

DATA_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | python3 -c "import sys, json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || \
             kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l | tr -d ' ')

if [ -n "$DATA_COUNT" ] && [ "$DATA_COUNT" != "0" ]; then
    echo -e "${GREEN}✓ SUCCESS! ConfigMap has $DATA_COUNT files${NC}"
    echo ""
    echo "Sample files in ConfigMap:"
    kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | python3 -c "import sys, json; d=json.load(sys.stdin); [print(f'  - {k}') for k in list(d.keys())[:10]]" 2>/dev/null || echo "  (checking...)"
    
    echo ""
    echo "Restarting nginx-thrift deployment..."
    kubectl rollout restart deployment/nginx-thrift-deployment
    echo -e "${GREEN}✓ Deployment restart initiated${NC}"
    echo ""
    echo "Monitor the pod:"
    echo "  kubectl get pods -l app=nginx-thrift -w"
else
    echo -e "${YELLOW}WARNING: ConfigMap still shows 0 files${NC}"
    echo ""
    echo "Checking ConfigMap:"
    kubectl get configmap nginx-lua-scripts -o yaml | head -40
fi

