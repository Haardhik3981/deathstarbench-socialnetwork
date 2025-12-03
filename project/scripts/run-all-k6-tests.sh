#!/bin/bash

# Script to run all k6 tests in sequence
# This will run: constant-load, stress-test, peak-test
# (endurance-test is skipped as it runs for 5+ hours)

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo "  $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
K6_TESTS_DIR="${PROJECT_ROOT}/k6-tests"

echo ""
echo "=========================================="
echo "  Running All k6 Tests"
echo "=========================================="
echo ""

# Check prerequisites
print_section "Step 1: Checking Prerequisites"

# Check k6 is installed
if ! command -v k6 &> /dev/null; then
    print_error "k6 is not installed"
    print_info "Install: brew install k6"
    exit 1
fi
K6_VERSION=$(k6 version | head -n 1)
print_success "k6 found: $K6_VERSION"

# Check port-forward is running
if ! lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    print_warn "Port-forward is not running on port 8080"
    print_info "Start it in another terminal:"
    echo "  kubectl port-forward svc/nginx-thrift 8080:8080"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "Port-forward is running on port 8080"
fi

# Set BASE_URL
BASE_URL="${BASE_URL:-http://localhost:8080}"
print_info "Using BASE_URL: $BASE_URL"

echo ""

# Test results directory
RESULTS_DIR="${PROJECT_ROOT}/k6-results"
mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

print_section "Step 2: Running Tests"
echo ""

# Test 1: Constant Load
print_section "Test 1: Constant Load Test"
print_info "Duration: ~3 minutes"
print_info "Load: 50 VUs, steady"
echo ""

OUTPUT_FILE="${RESULTS_DIR}/constant-load_${TIMESTAMP}.json"
if BASE_URL="$BASE_URL" k6 run --out json="$OUTPUT_FILE" "${K6_TESTS_DIR}/constant-load.js"; then
    print_success "Constant load test completed"
else
    print_error "Constant load test failed"
    exit 1
fi

echo ""
echo "---"
echo ""

# Wait a bit between tests
print_info "Waiting 30 seconds before next test..."
sleep 30

# Test 2: Stress Test
print_section "Test 2: Stress Test"
print_info "Duration: ~30+ minutes"
print_info "Load: Gradual ramp-up from 10 to 1000 VUs"
print_warn "NOTE: This test uses different endpoints that may not work"
echo ""

read -p "Run stress test? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    OUTPUT_FILE="${RESULTS_DIR}/stress-test_${TIMESTAMP}.json"
    if BASE_URL="$BASE_URL" k6 run --out json="$OUTPUT_FILE" "${K6_TESTS_DIR}/stress-test.js"; then
        print_success "Stress test completed"
    else
        print_warn "Stress test failed (may be due to endpoint issues)"
    fi
else
    print_info "Skipping stress test"
fi

echo ""
echo "---"
echo ""

# Wait a bit between tests
print_info "Waiting 30 seconds before next test..."
sleep 30

# Test 3: Peak Test
print_section "Test 3: Peak/Spike Test"
print_info "Duration: ~6 minutes"
print_info "Load: Sudden spike to 1000 VUs"
print_warn "NOTE: This test uses different endpoints that may not work"
echo ""

read -p "Run peak test? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    OUTPUT_FILE="${RESULTS_DIR}/peak-test_${TIMESTAMP}.json"
    if BASE_URL="$BASE_URL" k6 run --out json="$OUTPUT_FILE" "${K6_TESTS_DIR}/peak-test.js"; then
        print_success "Peak test completed"
    else
        print_warn "Peak test failed (may be due to endpoint issues)"
    fi
else
    print_info "Skipping peak test"
fi

echo ""
print_section "Test Summary"
echo ""
print_success "All requested tests completed!"
print_info "Results saved to: $RESULTS_DIR"
echo ""
print_info "To view results:"
echo "  ls -lh $RESULTS_DIR"
echo ""
print_info "Note: Endurance test (5+ hours) was skipped"
print_info "      Run it manually if needed:"
echo "  BASE_URL=$BASE_URL k6 run k6-tests/endurance-test.js"
echo ""

