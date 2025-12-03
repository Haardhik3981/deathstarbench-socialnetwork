#!/bin/bash

# Update nginx.conf to include env fqdn_suffix and update ConfigMap

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NGINX_CONF_SOURCE="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/conf/nginx.conf"

echo "=== Updating nginx.conf with env declaration ==="
echo ""

# Check if env fqdn_suffix is already there
if grep -q "^env fqdn_suffix;" "$NGINX_CONF_SOURCE"; then
    echo "✓ env fqdn_suffix already declared in nginx.conf"
else
    echo "✗ env fqdn_suffix NOT declared - this needs to be added manually"
    echo "  The nginx.conf file needs: env fqdn_suffix; (before the http block)"
    exit 1
fi

# Get CoreDNS for resolver
COREDNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || echo "")
if [ -z "$COREDNS_IP" ]; then
    RESOLVER="kube-dns.kube-system.svc.cluster.local"
else
    RESOLVER="$COREDNS_IP"
fi

# Fix resolver if needed
TEMP_CONF="/tmp/nginx.conf.fixed"
sed "s|resolver 127.0.0.11|resolver $RESOLVER|g" "$NGINX_CONF_SOURCE" > "$TEMP_CONF"

# Update ConfigMap
echo "Updating deathstarbench-config ConfigMap..."
SERVICE_CONFIG=$(kubectl get configmap deathstarbench-config -o jsonpath='{.data.service-config\.json}' 2>/dev/null || echo "")
JAEGER_JSON=$(kubectl get configmap deathstarbench-config -o jsonpath='{.data.jaeger-config\.json}' 2>/dev/null || echo "")
JAEGER_YML=$(kubectl get configmap deathstarbench-config -o jsonpath='{.data.jaeger-config\.yml}' 2>/dev/null || echo "")

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
sleep 15
kubectl wait --for=condition=ready pod -l app=nginx-thrift --timeout=60s || true

rm -f "$TEMP_CONF"

echo ""
echo "=== Done ==="

