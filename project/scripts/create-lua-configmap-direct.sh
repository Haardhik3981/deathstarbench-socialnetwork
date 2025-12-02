#!/bin/bash

# Direct fix: Create ConfigMap by explicitly listing each file

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMap (Direct Method) ==="
echo ""

cd "${LUA_SCRIPTS_DIR}"

# Delete old
kubectl delete configmap nginx-lua-scripts 2>/dev/null || true

echo "Creating ConfigMap with all Lua files explicitly..."
echo ""

# Create ConfigMap with all files in one command
kubectl create configmap nginx-lua-scripts \
  --from-file=api/home-timeline/read.lua=api/home-timeline/read.lua \
  --from-file=api/post/compose.lua=api/post/compose.lua \
  --from-file=api/user/follow.lua=api/user/follow.lua \
  --from-file=api/user/get_followee.lua=api/user/get_followee.lua \
  --from-file=api/user/get_follower.lua=api/user/get_follower.lua \
  --from-file=api/user/login.lua=api/user/login.lua \
  --from-file=api/user/register.lua=api/user/register.lua \
  --from-file=api/user/unfollow.lua=api/user/unfollow.lua \
  --from-file=api/user-timeline/read.lua=api/user-timeline/read.lua \
  --from-file=wrk2-api/home-timeline/read.lua=wrk2-api/home-timeline/read.lua \
  --from-file=wrk2-api/post/compose.lua=wrk2-api/post/compose.lua \
  --from-file=wrk2-api/user/follow.lua=wrk2-api/user/follow.lua \
  --from-file=wrk2-api/user/register.lua=wrk2-api/user/register.lua \
  --from-file=wrk2-api/user/unfollow.lua=wrk2-api/user/unfollow.lua \
  --from-file=wrk2-api/user-timeline/read.lua=wrk2-api/user-timeline/read.lua

echo ""
echo "Verifying..."
kubectl get configmap nginx-lua-scripts

DATA_COUNT=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' | grep -o '"[^"]*":' | wc -l | tr -d ' ')

if [ "$DATA_COUNT" -gt 0 ]; then
    echo ""
    echo "✓ SUCCESS! ConfigMap has $DATA_COUNT files"
    echo ""
    echo "Restarting nginx-thrift..."
    kubectl rollout restart deployment/nginx-thrift-deployment
    echo "✓ Done!"
else
    echo ""
    echo "Still showing 0 files. Checking YAML:"
    kubectl get configmap nginx-lua-scripts -o yaml | head -30
fi

cd "${PROJECT_ROOT}"

