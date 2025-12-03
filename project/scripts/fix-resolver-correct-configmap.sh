#!/bin/bash

# Fix resolver in the CORRECT ConfigMap (deathstarbench-config, not nginx-config)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONF_SOURCE="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/conf/nginx.conf"

echo "=== Fixing resolver in deathstarbench-config ConfigMap ==="
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

# Get current ConfigMap
echo "Getting current deathstarbench-config..."
kubectl get configmap deathstarbench-config -o yaml > /tmp/deathstarbench-config.yaml

# Extract other data
SERVICE_CONFIG=$(kubectl get configmap deathstarbench-config -o jsonpath='{.data.service-config\.json}' 2>/dev/null || echo "")
JAEGER_JSON=$(kubectl get configmap deathstarbench-config -o jsonpath='{.data.jaeger-config\.json}' 2>/dev/null || echo "")
JAEGER_YML=$(kubectl get configmap deathstarbench-config -o jsonpath='{.data.jaeger-config\.yml}' 2>/dev/null || echo "")

# Create new ConfigMap with fixed nginx.conf
echo "Updating deathstarbench-config ConfigMap..."
kubectl create configmap deathstarbench-config \
  --from-file=nginx.conf="$TEMP_CONF" \
  --from-literal=service-config.json="$SERVICE_CONFIG" \
  --from-literal=jaeger-config.json="$JAEGER_JSON" \
  --from-literal=jaeger-config.yml="$JAEGER_YML" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ ConfigMap updated"
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
    RESOLVER_LINE=$(kubectl exec "$NEW_POD" -- cat /usr/local/openresty/nginx/conf/nginx.conf 2>/dev/null | grep "resolver" | grep -v "^#" | head -1 || echo "")
    echo "Resolver line: $RESOLVER_LINE"
    if echo "$RESOLVER_LINE" | grep -q "$RESOLVER"; then
        echo "✓ Resolver is correct!"
    else
        echo "✗ Resolver is still wrong"
    fi
fi

rm -f "$TEMP_CONF" /tmp/deathstarbench-config.yaml

echo ""
echo "=== Done ==="

