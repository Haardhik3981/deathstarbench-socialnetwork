#!/bin/bash
# =============================================================================
# Push Metrics Loop - Collects metrics for Social Network microservices only
# =============================================================================
#
# Prerequisites:
#   1. kubectl configured for your cluster
#   2. Port-forward running: kubectl port-forward svc/pushgateway 9091:9091 -n cse239fall2025
#
# Usage:
#   ./push-metrics-loop.sh [interval_seconds]
#   Example: ./push-metrics-loop.sh 10
#
# =============================================================================

INTERVAL="${1:-10}"
PUSHGATEWAY="${PUSHGATEWAY_URL:-http://localhost:9091}"
NAMESPACE="cse239fall2025"

# Only collect metrics for these services
SERVICES_FILTER="nginx-thrift|compose-post-service|home-timeline-service|user-timeline-service|post-storage-service|social-graph-service|text-service|user-service|unique-id-service|url-shorten-service|user-mention-service"

echo "========================================"
echo "📊 Metrics Collector Started"
echo "========================================"
echo "Pushgateway: ${PUSHGATEWAY}"
echo "Namespace:   ${NAMESPACE}"
echo "Interval:    ${INTERVAL}s"
echo "Services:    11 microservices"
echo "========================================"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Check if pushgateway is reachable
if ! curl -s "${PUSHGATEWAY}/-/healthy" >/dev/null 2>&1; then
    echo "❌ ERROR: Cannot reach Pushgateway at ${PUSHGATEWAY}"
    echo ""
    echo "Make sure you have port-forward running:"
    echo "  kubectl port-forward svc/pushgateway 9091:9091 -n ${NAMESPACE}"
    echo ""
    exit 1
fi

echo "✅ Pushgateway is reachable"
echo ""

collect_and_push() {
    echo "$(date '+%H:%M:%S') Collecting metrics..."
    
    # Get pod metrics - filter for only the services we care about
    kubectl top pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep -E "${SERVICES_FILTER}" | while read pod cpu mem rest; do
        # Skip empty lines
        [[ -z "$pod" ]] && continue
        
        # Extract CPU (remove 'm' suffix)
        cpu_millicores=$(echo "$cpu" | sed 's/m//')
        
        # Extract memory and convert to bytes
        if [[ "$mem" =~ Mi$ ]]; then
            mem_val=$(echo "$mem" | sed 's/Mi//')
            mem_bytes=$((mem_val * 1024 * 1024))
        elif [[ "$mem" =~ Ki$ ]]; then
            mem_val=$(echo "$mem" | sed 's/Ki//')
            mem_bytes=$((mem_val * 1024))
        elif [[ "$mem" =~ Gi$ ]]; then
            mem_val=$(echo "$mem" | sed 's/Gi//')
            mem_bytes=$((mem_val * 1024 * 1024 * 1024))
        else
            mem_bytes=$(echo "$mem" | tr -cd '0-9')
            [[ -z "$mem_bytes" ]] && mem_bytes=0
        fi
        
        # Display
        mem_mib=$((mem_bytes / 1024 / 1024))
        printf "  %-45s CPU: %6sm  Memory: %6s MiB\n" "$pod" "$cpu_millicores" "$mem_mib"
        
        # Push to pushgateway
        curl -s --data-binary @- "${PUSHGATEWAY}/metrics/job/kubectl-top/pod/${pod}" <<EOF
# HELP ha_cpu_usage_millicores CPU usage in millicores from kubectl top
# TYPE ha_cpu_usage_millicores gauge
ha_cpu_usage_millicores{pod="${pod}",namespace="${NAMESPACE}"} ${cpu_millicores}
# HELP ha_memory_usage_bytes Memory usage in bytes from kubectl top
# TYPE ha_memory_usage_bytes gauge
ha_memory_usage_bytes{pod="${pod}",namespace="${NAMESPACE}"} ${mem_bytes}
EOF
    done
    
    echo "  ✅ Pushed to Pushgateway"
    echo ""
}

# Main loop
while true; do
    collect_and_push
    sleep ${INTERVAL}
done
