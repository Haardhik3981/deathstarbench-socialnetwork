#!/bin/bash

# Fix the resolver issue - verify and fix

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONF_SOURCE="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/conf/nginx.conf"

echo "=== Fixing nginx resolver ==="
echo ""

# Step 1: Get CoreDNS
echo "Step 1: Finding CoreDNS..."
COREDNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || echo "")

if [ -z "$COREDNS_IP" ]; then
    echo "  Using FQDN: kube-dns.kube-system.svc.cluster.local"
    RESOLVER="kube-dns.kube-system.svc.cluster.local"
else
    echo "  Found CoreDNS IP: $COREDNS_IP"
    RESOLVER="$COREDNS_IP"
fi
echo ""

# Step 2: Check current ConfigMap
echo "Step 2: Checking current ConfigMap..."
CURRENT_RESOLVER=$(kubectl get configmap nginx-config -o jsonpath='{.data.nginx\.conf}' 2>/dev/null | grep -oE 'resolver [^ ]+' | awk '{print $2}' | head -1 || echo "")

if [ -n "$CURRENT_RESOLVER" ]; then
    echo "  Current resolver: $CURRENT_RESOLVER"
    if [ "$CURRENT_RESOLVER" = "127.0.0.11" ]; then
        echo "  ✗ Still using Docker DNS - needs fixing"
    else
        echo "  ✓ Already using: $CURRENT_RESOLVER"
        echo "  If it's still not working, the pod may need a restart"
        exit 0
    fi
else
    echo "  ⚠ Could not read ConfigMap"
fi
echo ""

# Step 3: Fix the config file
echo "Step 3: Fixing nginx.conf..."
if [ ! -f "$NGINX_CONF_SOURCE" ]; then
    echo "  ✗ Source file not found: $NGINX_CONF_SOURCE"
    exit 1
fi

TEMP_CONF="/tmp/nginx.conf.fixed"
sed "s|resolver 127.0.0.11|resolver $RESOLVER|g" "$NGINX_CONF_SOURCE" > "$TEMP_CONF"

# Verify
if grep -q "resolver $RESOLVER" "$TEMP_CONF"; then
    echo "  ✓ Resolver fixed in temp file"
else
    echo "  ✗ Failed to fix resolver"
    exit 1
fi
echo ""

# Step 4: Update ConfigMap
echo "Step 4: Updating ConfigMap..."
kubectl create configmap nginx-config \
  --from-file=nginx.conf="$TEMP_CONF" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "  ✓ ConfigMap updated"
echo ""

# Step 5: Restart pod
echo "Step 5: Restarting nginx-thrift pod..."
kubectl delete pod -l app=nginx-thrift
echo "  Waiting for pod to restart..."
sleep 10
kubectl wait --for=condition=ready pod -l app=nginx-thrift --timeout=60s
echo "  ✓ Pod restarted"
echo ""

# Step 6: Verify
echo "Step 6: Verifying resolver in new pod..."
NEW_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NEW_POD" ]; then
    POD_RESOLVER=$(kubectl exec "$NEW_POD" -- cat /usr/local/openresty/nginx/conf/nginx.conf 2>/dev/null | grep -oE 'resolver [^ ]+' | awk '{print $2}' | head -1 || echo "")
    if [ "$POD_RESOLVER" = "$RESOLVER" ] || [ "$POD_RESOLVER" = "$COREDNS_IP" ]; then
        echo "  ✓ Pod is using correct resolver: $POD_RESOLVER"
    else
        echo "  ⚠ Pod resolver: $POD_RESOLVER (expected: $RESOLVER)"
        echo "  Showing resolver line from pod:"
        kubectl exec "$NEW_POD" -- cat /usr/local/openresty/nginx/conf/nginx.conf 2>/dev/null | grep "resolver" | head -1
    fi
fi

# Cleanup
rm -f "$TEMP_CONF"

echo ""
echo "=== Done ==="
echo "Test with:"
echo "  curl -X POST http://localhost:8080/wrk2-api/user/register \\"
echo "    -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "    -d 'user_id=99999&username=testuser&first_name=Test&last_name=User&password=test123'"

