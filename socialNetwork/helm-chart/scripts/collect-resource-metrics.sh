#!/bin/bash
# Collect CPU and Memory metrics using kubectl top and push to Pushgateway

set -e

PUSHGATEWAY="pushgateway.cse239fall2025.svc.cluster.local:9091"
NAMESPACE="cse239fall2025"

echo "📊 Collecting CPU and Memory metrics using kubectl top..."

# Check if kubectl top works
if ! kubectl top pods -n ${NAMESPACE} &>/dev/null; then
    echo "❌ Error: kubectl top is not available or metrics-server is not installed"
    echo "Skipping CPU/Memory collection..."
    exit 1
fi

# Get pod metrics
kubectl top pods -n ${NAMESPACE} --no-headers | while read pod cpu mem; do
    # Skip if empty
    [[ -z "$pod" ]] && continue
    
    # Extract CPU (remove 'm' and convert to cores)
    cpu_val=$(echo "$cpu" | sed 's/m//' | awk '{printf "%.3f", $1/1000}')
    
    # Extract memory (convert to bytes)
    if [[ "$mem" =~ Mi$ ]]; then
        mem_val=$(echo "$mem" | sed 's/Mi//' | awk '{printf "%.0f", $1*1024*1024}')
    elif [[ "$mem" =~ Ki$ ]]; then
        mem_val=$(echo "$mem" | sed 's/Ki//' | awk '{printf "%.0f", $1*1024}')
    elif [[ "$mem" =~ Gi$ ]]; then
        mem_val=$(echo "$mem" | sed 's/Gi//' | awk '{printf "%.0f", $1*1024*1024*1024}')
    else
        mem_val=$(echo "$mem" | sed 's/[^0-9]//g')
    fi
    
    echo "   ${pod}: CPU=${cpu_val} cores, Memory=${mem_val} bytes"
    
    # Push to pushgateway
    cat <<EOF | curl -s --data-binary @- http://${PUSHGATEWAY}/metrics/job/pod-resources/pod/${pod}
# TYPE pod_cpu_usage_cores gauge
pod_cpu_usage_cores{pod="${pod}",namespace="${NAMESPACE}"} ${cpu_val}
# TYPE pod_memory_usage_bytes gauge
pod_memory_usage_bytes{pod="${pod}",namespace="${NAMESPACE}"} ${mem_val}
EOF
done

echo ""
echo "✅ CPU and Memory metrics pushed to Pushgateway!"
echo ""
echo "📊 Query these in Grafana:"
echo "   pod_cpu_usage_cores{namespace=\"${NAMESPACE}\"}"
echo "   pod_memory_usage_bytes{namespace=\"${NAMESPACE}\"}"
echo ""
echo "Example queries:"
echo "   # Total CPU across all pods"
echo "   sum(pod_cpu_usage_cores{namespace=\"${NAMESPACE}\"})"
echo ""
echo "   # Top 5 CPU consuming pods"
echo "   topk(5, pod_cpu_usage_cores{namespace=\"${NAMESPACE}\"})"
echo ""
echo "   # Total memory across all pods (in GB)"
echo "   sum(pod_memory_usage_bytes{namespace=\"${NAMESPACE}\"}) / 1024 / 1024 / 1024"

