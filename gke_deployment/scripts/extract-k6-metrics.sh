#!/bin/bash

# Extract Key Metrics from k6 Summary Results
#
# WHAT THIS DOES:
# Extracts the essential metrics from k6 summary JSON file:
# - p50, p95, p99 latency (in milliseconds)
# - Throughput (requests per second)
# - Success rate (fraction of successful requests)
#
# The k6 JSON output is a stream format, so we parse the summary file instead,
# which is a proper JSON object with all aggregated metrics.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/k6-results"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed. Please install it first:"
    echo "  macOS: brew install jq"
    echo "  Linux: apt-get install jq"
    exit 1
fi

# Find summary file (preferred) or JSON file
if [ $# -eq 0 ]; then
    # Try to find summary file first (more reliable)
    SUMMARY_FILE=$(ls -t "${RESULTS_DIR}"/*_summary.txt 2>/dev/null | head -1)
    
    if [ -z "$SUMMARY_FILE" ]; then
        # Fall back to JSON file
        JSON_FILE=$(ls -t "${RESULTS_DIR}"/*.json 2>/dev/null | head -1)
    if [ -z "$JSON_FILE" ]; then
            print_error "No k6 result files found in ${RESULTS_DIR}"
        exit 1
    fi
        # Try to find corresponding summary file
        BASE_NAME=$(basename "$JSON_FILE" .json)
        SUMMARY_FILE="${RESULTS_DIR}/${BASE_NAME}_summary.txt"
    fi
else
    INPUT_FILE="$1"
    
    # If it's a summary file, use it directly
    if [[ "$INPUT_FILE" == *"_summary.txt" ]]; then
        SUMMARY_FILE="$INPUT_FILE"
    # If it's a JSON file, find corresponding summary
    elif [[ "$INPUT_FILE" == *.json ]]; then
        BASE_NAME=$(basename "$INPUT_FILE" .json)
        SUMMARY_FILE="${RESULTS_DIR}/${BASE_NAME}_summary.txt"
        if [ ! -f "$SUMMARY_FILE" ]; then
            print_error "Summary file not found: $SUMMARY_FILE"
            exit 1
        fi
    else
        SUMMARY_FILE="$INPUT_FILE"
    fi
    
    if [ ! -f "$SUMMARY_FILE" ]; then
        print_error "File not found: $SUMMARY_FILE"
        exit 1
    fi
fi

print_info "Extracting metrics from: $(basename "$SUMMARY_FILE")"
echo ""

# Extract metrics from summary file
# k6 summary format: metrics.http_req_duration.med = p50, p(95) = p95, etc.

# Latency metrics (in milliseconds)
# Note: k6 summary file stores latency in milliseconds already
P50=$(jq -r '.metrics.http_req_duration.med // empty' "$SUMMARY_FILE" 2>/dev/null)
if [ -n "$P50" ] && [ "$P50" != "null" ]; then
    P50_MS=$(printf "%.2f" "$P50")
else
    P50_MS="N/A"
fi

P95=$(jq -r '.metrics.http_req_duration."p(95)" // empty' "$SUMMARY_FILE" 2>/dev/null)
if [ -n "$P95" ] && [ "$P95" != "null" ]; then
    P95_MS=$(printf "%.2f" "$P95")
else
    P95_MS="N/A"
fi

# Try to get p99 - may not always be present in summary
P99=$(jq -r '.metrics.http_req_duration."p(99)" // .metrics.http_req_duration."p(99)" // empty' "$SUMMARY_FILE" 2>/dev/null)
if [ -n "$P99" ] && [ "$P99" != "null" ] && [ "$P99" != "empty" ]; then
    P99_MS=$(printf "%.2f" "$P99")
else
    # p99 might not be in summary, that's okay
    P99_MS="N/A"
fi

# Throughput (requests per second)
THROUGHPUT=$(jq -r '.metrics.http_reqs.rate // "N/A"' "$SUMMARY_FILE" 2>/dev/null)
if [ "$THROUGHPUT" != "N/A" ] && [ -n "$THROUGHPUT" ] && [ "$THROUGHPUT" != "null" ]; then
    THROUGHPUT=$(printf "%.2f" "$THROUGHPUT")
fi

# Success rate (1 - error rate)
ERROR_RATE=$(jq -r '.metrics.http_req_failed.value // 0' "$SUMMARY_FILE" 2>/dev/null)
if [ -n "$ERROR_RATE" ] && [ "$ERROR_RATE" != "null" ]; then
    SUCCESS_RATE=$(echo "1 - $ERROR_RATE" | bc -l 2>/dev/null | xargs printf "%.4f")
    SUCCESS_RATE_PCT=$(echo "$SUCCESS_RATE * 100" | bc -l 2>/dev/null | xargs printf "%.2f")
else
    SUCCESS_RATE="N/A"
    SUCCESS_RATE_PCT="N/A"
fi

# Display metrics
echo "=== Key Metrics ==="
echo "p50 Latency:     ${P50_MS} ms"
echo "p95 Latency:     ${P95_MS} ms"
if [ "$P99_MS" != "N/A" ]; then
    echo "p99 Latency:     ${P99_MS} ms"
else
    echo "p99 Latency:     N/A (not available in summary)"
fi
echo "Throughput:      ${THROUGHPUT} req/s"
echo "Success Rate:    ${SUCCESS_RATE_PCT}% (${SUCCESS_RATE})"
echo ""

# Export to CSV (simplified - only what you care about)
CSV_FILE="${SUMMARY_FILE%_summary.txt}_metrics.csv"
cat > "$CSV_FILE" <<EOF
Metric,Value
p50_latency_ms,${P50_MS}
p95_latency_ms,${P95_MS}
p99_latency_ms,${P99_MS}
throughput_req_per_sec,${THROUGHPUT}
success_rate,${SUCCESS_RATE}
success_rate_percent,${SUCCESS_RATE_PCT}
EOF

print_info "Metrics exported to CSV: $(basename "$CSV_FILE")"
echo ""
print_info "CSV file location: $CSV_FILE"

