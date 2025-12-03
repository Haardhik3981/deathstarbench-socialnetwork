#!/bin/bash

# Fix nginx resolver to use Kubernetes CoreDNS instead of Docker DNS

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONF_SOURCE="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/conf/nginx.conf"
NGINX_CONF_TEMP="/tmp/nginx.conf.fixed"

echo "=== Fixing nginx resolver for Kubernetes ==="
echo ""

# Get CoreDNS service IP (or use FQDN)
echo "Step 1: Finding CoreDNS service..."
COREDNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ -z "$COREDNS_IP" ]; then
    # Try alternative service name
    COREDNS_IP=$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || echo "")
fi

if [ -z "$COREDNS_IP" ]; then
    echo "  ⚠ Could not find CoreDNS IP, using FQDN instead"
    RESOLVER="kube-dns.kube-system.svc.cluster.local"
else
    echo "  ✓ Found CoreDNS at: $COREDNS_IP"
    RESOLVER="$COREDNS_IP"
fi

echo "  Using resolver: $RESOLVER"
echo ""

# Check if source file exists
if [ ! -f "$NGINX_CONF_SOURCE" ]; then
    echo "✗ ERROR: nginx.conf source not found at: $NGINX_CONF_SOURCE"
    exit 1
fi

# Fix the resolver line
echo "Step 2: Fixing resolver in nginx.conf..."
sed "s|resolver 127.0.0.11|resolver $RESOLVER|g" "$NGINX_CONF_SOURCE" > "$NGINX_CONF_TEMP"

# Verify the change
if grep -q "resolver $RESOLVER" "$NGINX_CONF_TEMP"; then
    echo "  ✓ Resolver fixed"
else
    echo "  ✗ Failed to fix resolver"
    exit 1
fi

# Update the ConfigMap
echo ""
echo "Step 3: Updating nginx-config ConfigMap..."
kubectl create configmap nginx-config \
  --from-file=nginx.conf="$NGINX_CONF_TEMP" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ ConfigMap updated"
echo ""

# Restart nginx-thrift
echo "Step 4: Restarting nginx-thrift deployment..."
kubectl rollout restart deployment/nginx-thrift-deployment
echo "  Waiting for rollout..."
kubectl rollout status deployment/nginx-thrift-deployment --timeout=60s
echo "  ✓ Deployment restarted"
echo ""

# Cleanup
rm -f "$NGINX_CONF_TEMP"

echo "=== Done ==="
echo ""
echo "The resolver has been fixed. Test with:"
echo "  curl -X POST http://localhost:8080/wrk2-api/user/register \\"
echo "    -H 'Content-Type: application/x-www-form-urlencoded' \\"
echo "    -d 'user_id=99999&username=testuser&first_name=Test&last_name=User&password=test123'"

