#!/bin/bash

# Simple verification script - check the basics

set -e

echo "=== Basic Verification ==="
echo ""

# 1. Check pods are running
echo "1. Checking pods..."
kubectl get pods -l app=nginx-thrift 2>&1 | grep -v "NAME" || echo "  ✗ No nginx-thrift pods"
kubectl get pods -l app=user-service 2>&1 | grep -v "NAME" || echo "  ✗ No user-service pods"
echo ""

# 2. Check services exist
echo "2. Checking services..."
kubectl get svc nginx-thrift 2>&1 | grep -v "NAME" || echo "  ✗ nginx-thrift service missing"
kubectl get svc user-service 2>&1 | grep -v "NAME" || echo "  ✗ user-service service missing"
echo ""

# 3. Check ConfigMaps exist
echo "3. Checking critical ConfigMaps..."
REQUIRED_CMAPS=(
  "nginx-lua-scripts-wrk2-api-user"
  "nginx-lua-scripts-api-user"
  "deathstarbench-config"
  "nginx-config"
)

for cm in "${REQUIRED_CMAPS[@]}"; do
  if kubectl get configmap "$cm" &>/dev/null; then
    DATA_COUNT=$(kubectl get configmap "$cm" -o jsonpath='{.data}' 2>/dev/null | grep -o '":' | wc -l | tr -d ' ')
    if [ "$DATA_COUNT" -gt 0 ]; then
      echo "  ✓ $cm (has data)"
    else
      echo "  ✗ $cm (exists but empty!)"
    fi
  else
    echo "  ✗ $cm (missing!)"
  fi
done
echo ""

# 4. Check if port-forward is running
echo "4. Checking port-forward..."
if lsof -ti:8080 &>/dev/null; then
  echo "  ✓ Port 8080 is in use (port-forward likely running)"
else
  echo "  ✗ Port 8080 is not in use - start port-forward with:"
  echo "    kubectl port-forward svc/nginx-thrift 8080:8080"
fi
echo ""

# 5. Test basic connectivity
echo "5. Testing basic connectivity..."
NGINX_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$NGINX_POD" ]; then
  echo "  nginx-thrift pod: $NGINX_POD"
  
  # Check if nginx is listening
  if kubectl exec "$NGINX_POD" -- sh -c "netstat -tln 2>/dev/null | grep 8080 || ss -tln 2>/dev/null | grep 8080 || echo 'netstat/ss not available'" 2>&1 | grep -q "8080"; then
    echo "  ✓ nginx is listening on port 8080"
  else
    echo "  ⚠ Cannot verify nginx is listening (netstat/ss not available)"
  fi
  
  # Check if Lua scripts are mounted
  if kubectl exec "$NGINX_POD" -- test -f /usr/local/openresty/nginx/lua-scripts/wrk2-api/user/register.lua 2>/dev/null; then
    echo "  ✓ register.lua is mounted"
  else
    echo "  ✗ register.lua is NOT mounted!"
  fi
else
  echo "  ✗ No nginx-thrift pod found"
fi
echo ""

# 6. Simple HTTP test
echo "6. Testing HTTP endpoint..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>&1 | grep -q "200\|404\|403"; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>&1)
  echo "  ✓ nginx-thrift responds (HTTP $HTTP_CODE)"
else
  echo "  ✗ nginx-thrift not responding on localhost:8080"
  echo "    Make sure port-forward is running: kubectl port-forward svc/nginx-thrift 8080:8080"
fi
echo ""

echo "=== Summary ==="
echo "If all checks pass, try making a request:"
echo "  curl -X POST http://localhost:8080/wrk2-api/user/register \\"
echo "    -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "    -d 'user_id=99999&username=testuser&first_name=Test&last_name=User&password=test123'"

