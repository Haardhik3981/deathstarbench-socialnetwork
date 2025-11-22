#!/bin/bash

# k6 Test Runner Script
#
# WHAT THIS DOES:
# This script provides a convenient way to run k6 load tests. It handles
# setting the correct base URL, running different test types, and saving
# results.
#
# USAGE:
#   ./run-k6-tests.sh constant-load
#   ./run-k6-tests.sh peak-test
#   ./run-k6-tests.sh stress-test
#   ./run-k6-tests.sh endurance-test
#   ./run-k6-tests.sh all

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K6_TESTS_DIR="${PROJECT_ROOT}/k6-tests"
RESULTS_DIR="${PROJECT_ROOT}/k6-results"

# Configuration
BASE_URL="${BASE_URL:-http://localhost:8080}"
TEST_TYPE="${1:-constant-load}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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
check_k6() {
    if ! command -v k6 &> /dev/null; then
        print_error "k6 is not installed."
        print_info "Install from: https://k6.io/docs/getting-started/installation/"
        exit 1
    fi
}

# Create results directory
create_results_dir() {
    mkdir -p "${RESULTS_DIR}"
    print_info "Results will be saved to: ${RESULTS_DIR}"
}

# Run a specific test
run_test() {
    local test_name=$1
    local test_file="${K6_TESTS_DIR}/${test_name}.js"
    
    if [ ! -f "${test_file}" ]; then
        print_error "Test file not found: ${test_file}"
        exit 1
    fi
    
    print_info "Running ${test_name}..."
    print_info "Target URL: ${BASE_URL}"
    
    # Generate timestamp for results
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local result_file="${RESULTS_DIR}/${test_name}_${timestamp}.json"
    local summary_file="${RESULTS_DIR}/${test_name}_${timestamp}_summary.txt"
    
    # Run k6 test
    # --out json: Save results as JSON
    # --summary-export: Export summary statistics
    BASE_URL="${BASE_URL}" k6 run \
        --out "json=${result_file}" \
        --summary-export="${summary_file}" \
        "${test_file}"
    
    print_info "Test completed!"
    print_info "Results saved to: ${result_file}"
    print_info "Summary saved to: ${summary_file}"
}

# Run all tests
run_all_tests() {
    print_info "Running all k6 tests..."
    
    local tests=("constant-load" "peak-test" "stress-test")
    
    for test in "${tests[@]}"; do
        echo ""
        print_info "========================================="
        print_info "Running ${test}..."
        print_info "========================================="
        echo ""
        
        run_test "${test}"
        
        # Wait between tests to let system recover
        if [ "${test}" != "stress-test" ]; then
            print_info "Waiting 2 minutes before next test..."
            sleep 120
        fi
    done
    
    print_warn "Endurance test skipped (runs for 5+ hours)"
    print_info "To run endurance test manually:"
    print_info "  BASE_URL=${BASE_URL} k6 run ${K6_TESTS_DIR}/endurance-test.js"
}

# Main
main() {
    check_k6
    create_results_dir
    
    case "${TEST_TYPE}" in
        constant-load|peak-test|stress-test|endurance-test)
            run_test "${TEST_TYPE}"
            ;;
        all)
            run_all_tests
            ;;
        *)
            print_error "Unknown test type: ${TEST_TYPE}"
            echo ""
            echo "Usage: $0 [test-type]"
            echo ""
            echo "Test types:"
            echo "  constant-load  - Constant steady load test"
            echo "  peak-test      - Sudden traffic spike test"
            echo "  stress-test    - Gradual ramp-up stress test"
            echo "  endurance-test - Long-duration soak test"
            echo "  all            - Run all tests (except endurance)"
            echo ""
            echo "Environment variables:"
            echo "  BASE_URL - Target URL (default: http://localhost:8080)"
            exit 1
            ;;
    esac
}

main

