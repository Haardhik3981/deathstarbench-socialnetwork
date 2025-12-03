#!/bin/bash

# Force fix the resolver by directly updating the ConfigMap

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONF_SOURCE="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/conf/nginx.conf"

echo "=== Force fixing nginx resolver ==="
echo ""

# Get CoreDNS
COREDNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || echo "")

if [ -z "$COREDNS_IP" ]; then
    RESOLVER="kube-dns.kube-system.svc.cluster.local"
else
    RESOLVER="$COREDNS_IP"
fi

echo "Using resolver: $RESOLVER"
echo ""

# Fix the file
TEMP_CONF="/tmp/nginx.conf.fixed"
sed "s|resolver 127.0.0.11|resolver $RESOLVER|g" "$NGINX_CONF_SOURCE" > "$TEMP_CONF"

# Verify it changed
if ! grep -q "resolver $RESOLVER" "$TEMP_CONF"; then
    echo "✗ Failed to fix resolver in temp file"
    exit 1
fi

echo "✓ Fixed resolver in temp file"
echo ""

# Delete and recreate ConfigMap to force update
echo "Deleting old ConfigMap..."
kubectl delete configmap nginx-config 2>/dev/null || true
sleep 2

echo "Creating new ConfigMap..."
kubectl create configmap nginx-config \
  --from-file=nginx.conf="$TEMP_CONF"

echo "✓ ConfigMap recreated"
echo ""

# Restart pod
echo "Restarting pod..."
kubectl delete pod -l app=nginx-thrift
echo "Waiting for pod..."
sleep 15
kubectl wait --for=condition=ready pod -l app=nginx-thrift --timeout=60s || true

# Verify
NEW_POD=$(kubectl get pods -l app=nginx-thrift --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NEW_POD" ]; then
    echo ""
    echo "Verifying resolver in pod $NEW_POD..."
    POD_RESOLVER=$(kubectl exec "$NEW_POD" -- cat /usr/local/openresty/nginx/conf/nginx.conf 2>/dev/null | grep "resolver" | grep -v "^#" | awk '{print $2}' | head -1 || echo "")
    echo "Pod resolver: $POD_RESOLVER"
    if [ "$POD_RESOLVER" = "$RESOLVER" ] || [ "$POD_RESOLVER" = "$COREDNS_IP" ]; then
        echo "✓ Resolver is correct!"
    else
        echo "✗ Resolver is still wrong"
    fi
fi

rm -f "$TEMP_CONF"

echo ""
echo "=== Done ==="

