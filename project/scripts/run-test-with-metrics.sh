#!/bin/bash

# Run k6 Test and Extract Metrics
#
# This script runs a k6 test, records timestamps, and extracts metrics
# for easy correlation with Prometheus data.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
K6_TESTS_DIR="${PROJECT_ROOT}/k6-tests"
RESULTS_DIR="${PROJECT_ROOT}/k6-results"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if k6 is installed
if ! command -v k6 &> /dev/null; then
    print_error "k6 is not installed. Please install it first:"
    print_info "  macOS: brew install k6"
    print_info "  Linux: See https://k6.io/docs/getting-started/installation/"
    exit 1
fi

# Parse arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 <test-name> [BASE_URL]"
    echo ""
    echo "Available tests:"
    echo "  quick-test          - Low load validation (10 VUs, 20s) - Verify system works"
    echo "  constant-load       - Baseline performance (50 VUs, 3 min) - Steady load"
    echo "  sweet-test          - ⭐ Recommended for HPA demo (350 VUs, 9 min) - Autoscaling demo"
    echo "  peak-test           - High load spike (400 VUs, ~10 min) - Extreme load test"
    echo "  stress-test         - Gradual ramp-up (10→400 VUs, ~35 min) - Find breaking point"
    echo "  cpu-intensive-test  - ⭐ CPU-focused load (10→1000 VUs, ~20 min) - Force CPU-based scaling"
    echo "  endurance-test      - Long duration (200 VUs, 2.5 hours) - Stability testing"
    echo "  vpa-learning-test   - ⭐ Recommended for VPA demo (~19.5 min) - VPA learning test"
    echo ""
    echo "Examples:"
    echo "  $0 sweet-test"
    echo "  $0 vpa-learning-test"
    echo "  BASE_URL=http://localhost:8080 $0 quick-test"
    exit 0
fi

TEST_TYPE="${1:-constant-load}"
BASE_URL="${BASE_URL:-http://localhost:8080}"

# Validate test type
if [ ! -f "${K6_TESTS_DIR}/${TEST_TYPE}.js" ]; then
    print_error "Test file not found: ${K6_TESTS_DIR}/${TEST_TYPE}.js"
    echo ""
    print_info "Available tests:"
    echo "  quick-test          - Low load validation (10 VUs, 20s)"
    echo "  constant-load       - Baseline performance (50 VUs, 3 min)"
    echo "  sweet-test          - ⭐ Recommended for HPA demo (350 VUs, 9 min)"
    echo "  peak-test           - High load spike (400 VUs, ~10 min)"
    echo "  stress-test         - Gradual ramp-up (10→400 VUs, ~35 min)"
    echo "  cpu-intensive-test  - ⭐ CPU-focused load (10→1000 VUs, ~20 min) - Force CPU-based scaling"
    echo "  endurance-test      - Long duration (200 VUs, 2.5 hours)"
    echo "  vpa-learning-test   - ⭐ Recommended for VPA demo (~19.5 min)"
    echo ""
    print_info "Usage: $0 <test-name>"
    print_info "Run '$0 --help' for more information"
    exit 1
fi

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
JSON_OUTPUT="${RESULTS_DIR}/${TEST_TYPE}_${TIMESTAMP}.json"
SUMMARY_OUTPUT="${RESULTS_DIR}/${TEST_TYPE}_${TIMESTAMP}_summary.txt"
METRICS_OUTPUT="${RESULTS_DIR}/${TEST_TYPE}_${TIMESTAMP}_metrics.txt"

print_section "Running k6 Test: ${TEST_TYPE}"
echo ""
print_info "Test file: ${TEST_TYPE}.js"
print_info "Base URL: ${BASE_URL}"
print_info "Output: ${JSON_OUTPUT}"
echo ""

# Record test start time (UTC)
TEST_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
print_info "Test start time (UTC): ${TEST_START}"
echo ""

# Run k6 test
print_info "Starting k6 test..."
echo ""

BASE_URL="${BASE_URL}" k6 run \
    --out "json=${JSON_OUTPUT}" \
    --summary-export="${SUMMARY_OUTPUT}" \
    "${K6_TESTS_DIR}/${TEST_TYPE}.js"

# Record test end time (UTC)
TEST_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
print_info "Test end time (UTC): ${TEST_END}"
echo ""

# Extract metrics from summary file (more reliable than JSON stream)
print_section "Extracting Metrics"
if [ -f "${SCRIPT_DIR}/extract-k6-metrics.sh" ]; then
    # Use summary file instead of JSON (summary is proper JSON, JSON output is a stream)
    "${SCRIPT_DIR}/extract-k6-metrics.sh" "${SUMMARY_OUTPUT}" > "${METRICS_OUTPUT}"
    echo ""
    cat "${METRICS_OUTPUT}"
    
    # Also create CSV file
    CSV_FILE="${RESULTS_DIR}/${TEST_TYPE}_${TIMESTAMP}_metrics.csv"
    "${SCRIPT_DIR}/extract-k6-metrics.sh" "${SUMMARY_OUTPUT}" | grep -A 10 "Key Metrics" > /dev/null 2>&1 || true
    # CSV is created by extract script
else
    print_warn "extract-k6-metrics.sh not found, skipping metric extraction"
fi

echo ""
print_section "Test Complete"
echo ""
print_info "Results saved to:"
echo "  JSON:    ${JSON_OUTPUT}"
echo "  Summary: ${SUMMARY_OUTPUT}"
echo "  Metrics: ${METRICS_OUTPUT}"
echo ""

print_info "Time Range for Prometheus/Grafana Queries:"
echo "  Start: ${TEST_START}"
echo "  End:   ${TEST_END}"
echo ""

print_info "To view metrics in Prometheus:"
echo "  1. kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo "  2. Open http://localhost:9090"
echo "  3. Set time range to: ${TEST_START} to ${TEST_END}"
echo "  4. Query system metrics (CPU, memory, pod count)"
echo ""

print_info "To view metrics in Grafana:"
echo "  1. kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo "  2. Open http://localhost:3000"
echo "  3. Set time range to: ${TEST_START} to ${TEST_END}"
echo "  4. View dashboards"
echo ""

print_info "To extract k6 metrics:"
echo "  ./scripts/extract-k6-metrics.sh ${JSON_OUTPUT}"
echo ""

