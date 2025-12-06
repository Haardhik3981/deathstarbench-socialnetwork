#!/bin/bash
# Script to check what metrics are available in Prometheus
# Helps identify the correct metric names for request rate queries

set -e

echo "=== Prometheus Metrics Discovery ==="
echo ""
echo "This script will help you find available metrics for request rate monitoring."
echo ""

# Check if Prometheus is accessible
echo "1. Checking Prometheus accessibility..."
if ! kubectl get svc -n monitoring prometheus &>/dev/null; then
    echo "   ❌ Prometheus service not found in 'monitoring' namespace"
    echo "   Trying to find Prometheus in other namespaces..."
    kubectl get svc -A | grep prometheus || echo "   ❌ Prometheus not found"
    exit 1
fi

echo "   ✅ Prometheus found in 'monitoring' namespace"
echo ""

# Port-forward Prometheus
echo "2. Setting up port-forward to Prometheus..."
echo "   Run this in another terminal:"
echo "   kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo ""
echo "   Then open http://localhost:9090 in your browser"
echo ""

# Check for common HTTP metrics
echo "3. Common metric names to search for in Prometheus:"
echo ""
echo "   HTTP Request Metrics:"
echo "   - http_requests_total"
echo "   - http_request_total"
echo "   - requests_total"
echo "   - nginx_http_requests_total"
echo "   - http_server_requests_seconds_count"
echo ""
echo "   Network Metrics (if HTTP metrics not available):"
echo "   - container_network_transmit_bytes_total"
echo "   - container_network_receive_bytes_total"
echo ""
echo "   Pod Metrics:"
echo "   - kube_pod_info"
echo "   - kube_pod_status_phase"
echo ""

# Try to query Prometheus API directly
echo "4. Attempting to query Prometheus API..."
echo ""

PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$PROMETHEUS_POD" ]; then
    echo "   Found Prometheus pod: $PROMETHEUS_POD"
    echo ""
    echo "   Querying for HTTP-related metrics..."
    
    # Query Prometheus API for metrics containing "http" or "request"
    kubectl exec -n monitoring "$PROMETHEUS_POD" -- wget -qO- 'http://localhost:9090/api/v1/label/__name__/values' 2>/dev/null | \
        grep -iE "(http|request)" | head -20 || echo "   (Could not query metrics directly)"
    
    echo ""
    echo "   To see all available metrics, run:"
    echo "   kubectl exec -n monitoring $PROMETHEUS_POD -- wget -qO- 'http://localhost:9090/api/v1/label/__name__/values' | jq -r '.data[]' | grep -i http"
    echo ""
else
    echo "   Could not find Prometheus pod"
    echo "   You can still access Prometheus UI to browse metrics"
fi

echo ""
echo "5. Recommended queries to try in Prometheus/Grafana:"
echo ""
echo "   A. Total request rate (try these variations):"
echo "      sum(rate(http_requests_total{service=\"user-service\"}[1m]))"
echo "      sum(rate(container_network_transmit_bytes_total{pod=~\"user-service-deployment-.*\"}[1m]))"
echo ""
echo "   B. Request rate per pod:"
echo "      sum(rate(http_requests_total{service=\"user-service\"}[1m])) by (pod)"
echo ""
echo "   C. Pod count:"
echo "      count(kube_pod_info{pod=~\"user-service-deployment-.*\"})"
echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Port-forward Prometheus:"
echo "   kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo ""
echo "2. Open Prometheus UI:"
echo "   http://localhost:9090"
echo ""
echo "3. Go to 'Graph' tab and try the queries above"
echo ""
echo "4. Check 'Status → Targets' to see if services are being scraped"
echo ""
echo "5. Browse available metrics in the 'Metrics' dropdown"
echo ""

