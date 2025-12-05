#!/bin/bash
# Extract k6 latency metrics and push to Pushgateway for Grafana visualization

set -e

PUSHGATEWAY="http://pushgateway.cse239fall2025.svc.cluster.local:9091"
JOB_NAME="${1:-k6-stress-test}"
NAMESPACE="cse239fall2025"

echo "📊 Extracting k6 metrics from logs..."

# Get k6 logs
K6_LOGS=$(kubectl logs -n ${NAMESPACE} -l app=k6-stress-test --tail=10000 2>/dev/null || \
          kubectl logs -n ${NAMESPACE} -l app=k6-load-test --tail=10000 2>/dev/null || \
          echo "")

if [ -z "$K6_LOGS" ]; then
    echo "❌ Error: Could not find k6 logs. Make sure k6 job is running or completed."
    exit 1
fi

# Extract latency metrics from k6 output
# Format: http_req_duration........: avg=123.45ms min=12.34ms med=98.76ms max=567.89ms p(90)=234.56ms p(95)=345.67ms p(99)=456.78ms

DURATION_LINE=$(echo "$K6_LOGS" | grep -i "http_req_duration" | tail -1)

if [ -z "$DURATION_LINE" ]; then
    echo "❌ Error: Could not find latency metrics in k6 logs."
    echo "Looking for 'http_req_duration' in logs..."
    exit 1
fi

# Extract values using grep/sed/awk
AVG=$(echo "$DURATION_LINE" | grep -oP 'avg=\K[0-9.]+' | head -1 || echo "0")
MIN=$(echo "$DURATION_LINE" | grep -oP 'min=\K[0-9.]+' | head -1 || echo "0")
MED=$(echo "$DURATION_LINE" | grep -oP 'med=\K[0-9.]+' | head -1 || echo "0")
MAX=$(echo "$DURATION_LINE" | grep -oP 'max=\K[0-9.]+' | head -1 || echo "0")
P90=$(echo "$DURATION_LINE" | grep -oP 'p\(90\)=\K[0-9.]+' | head -1 || echo "0")
P95=$(echo "$DURATION_LINE" | grep -oP 'p\(95\)=\K[0-9.]+' | head -1 || echo "0")
P99=$(echo "$DURATION_LINE" | grep -oP 'p\(99\)=\K[0-9.]+' | head -1 || echo "0")

# Extract request metrics
REQ_LINE=$(echo "$K6_LOGS" | grep -i "http_reqs" | tail -1)
REQ_TOTAL=$(echo "$REQ_LINE" | grep -oP ':\s+\K[0-9]+' | head -1 || echo "0")
REQ_RATE=$(echo "$REQ_LINE" | grep -oP '([0-9.]+)\s+/s' | head -1 | grep -oP '[0-9.]+' || echo "0")

# Extract error rate
ERROR_LINE=$(echo "$K6_LOGS" | grep -i "http_req_failed" | tail -1)
ERROR_RATE=$(echo "$ERROR_LINE" | grep -oP '([0-9.]+)%' | head -1 | grep -oP '[0-9.]+' || echo "0")

echo "✅ Extracted metrics:"
echo "   Average Latency: ${AVG}ms"
echo "   Median (p50): ${MED}ms"
echo "   p95: ${P95}ms"
echo "   p99: ${P99}ms"
echo "   Min: ${MIN}ms"
echo "   Max: ${MAX}ms"
echo "   Total Requests: ${REQ_TOTAL}"
echo "   Request Rate: ${REQ_RATE} req/s"
echo "   Error Rate: ${ERROR_RATE}%"

# Push to Pushgateway
echo ""
echo "📤 Pushing metrics to Pushgateway..."

METRICS=$(cat <<EOF
# TYPE k6_latency_avg_ms gauge
k6_latency_avg_ms ${AVG}
# TYPE k6_latency_median_ms gauge
k6_latency_median_ms ${MED}
# TYPE k6_latency_p90_ms gauge
k6_latency_p90_ms ${P90}
# TYPE k6_latency_p95_ms gauge
k6_latency_p95_ms ${P95}
# TYPE k6_latency_p99_ms gauge
k6_latency_p99_ms ${P99}
# TYPE k6_latency_min_ms gauge
k6_latency_min_ms ${MIN}
# TYPE k6_latency_max_ms gauge
k6_latency_max_ms ${MAX}
# TYPE k6_requests_total counter
k6_requests_total ${REQ_TOTAL}
# TYPE k6_request_rate gauge
k6_request_rate ${REQ_RATE}
# TYPE k6_error_rate_percent gauge
k6_error_rate_percent ${ERROR_RATE}
EOF
)

# Push to Pushgateway
RESPONSE=$(echo "$METRICS" | curl -s -w "\n%{http_code}" --data-binary @- ${PUSHGATEWAY}/metrics/job/${JOB_NAME})

HTTP_CODE=$(echo "$RESPONSE" | tail -1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Successfully pushed metrics to Pushgateway!"
    echo ""
    echo "📊 Query these in Grafana:"
    echo "   k6_latency_avg_ms{job=\"${JOB_NAME}\"}"
    echo "   k6_latency_p95_ms{job=\"${JOB_NAME}\"}"
    echo "   k6_latency_p99_ms{job=\"${JOB_NAME}\"}"
else
    echo "❌ Error pushing to Pushgateway. HTTP code: $HTTP_CODE"
    echo "Response: $(echo "$RESPONSE" | head -n -1)"
    exit 1
fi

