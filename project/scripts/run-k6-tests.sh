#!/bin/bash

# k6 Test Runner Script
#
# WHAT THIS DOES:
# This script provides a convenient way to run k6 load tests. It handles
# setting the correct base URL, running different test types, and saving
# results.
#
# USAGE:
#   ./run-k6-tests.sh quick-test      - Quick 20-second validation test (run this first!)
#   ./run-k6-tests.sh constant-load
#   ./run-k6-tests.sh peak-test
#   ./run-k6-tests.sh stress-test
#   ./run-k6-tests.sh endurance-test
#   ./run-k6-tests.sh all             - Runs quick-test first, then other tests

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K6_TESTS_DIR="${PROJECT_ROOT}/k6-tests"
RESULTS_DIR="${PROJECT_ROOT}/k6-results"

# Configuration
# BASE_URL can be set manually, or we'll try to detect it
# For local: http://localhost:8080
# For GKE: http://<loadbalancer-ip>:8080
BASE_URL="${BASE_URL}"
TEST_TYPE="${1:-constant-load}"
ENVIRONMENT="${ENVIRONMENT:-auto}"  # auto, local, gke

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

# Detect and set BASE_URL based on environment
detect_base_url() {
    if [ -n "${BASE_URL}" ]; then
        print_info "Using provided BASE_URL: ${BASE_URL}"
        return
    fi
    
    # Try to detect environment
    if [ "${ENVIRONMENT}" = "auto" ]; then
        # Check if kubectl is available and configured
        if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null 2>&1; then
            ENVIRONMENT="gke"
            print_info "Detected Kubernetes cluster, assuming GKE environment"
        else
            ENVIRONMENT="local"
            print_info "No Kubernetes cluster detected, assuming local environment"
        fi
    fi
    
    if [ "${ENVIRONMENT}" = "gke" ]; then
        print_info "Attempting to get LoadBalancer IP from Kubernetes..."
        
        # Try to get nginx-thrift service LoadBalancer IP
        NGINX_IP=$(kubectl get service nginx-thrift-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        
        if [ -z "${NGINX_IP}" ] || [ "${NGINX_IP}" = "null" ]; then
            # Try legacy nginx-service name
            NGINX_IP=$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        fi
        
        if [ -n "${NGINX_IP}" ] && [ "${NGINX_IP}" != "null" ]; then
            BASE_URL="http://${NGINX_IP}:8080"
            print_info "Found LoadBalancer IP: ${BASE_URL}"
        else
            print_warn "Could not find LoadBalancer IP. Service may still be provisioning."
            print_info "You can:"
            print_info "  1. Wait a few minutes and run again"
            print_info "  2. Set BASE_URL manually: BASE_URL=http://<ip>:8080 $0 ${TEST_TYPE}"
            print_info "  3. Use port-forward: kubectl port-forward svc/nginx-thrift-service 8080:8080"
            print_info "     Then set: BASE_URL=http://localhost:8080 $0 ${TEST_TYPE}"
            exit 1
        fi
    else
        # Local environment
        BASE_URL="http://localhost:8080"
        print_info "Using local BASE_URL: ${BASE_URL}"
        print_info "Make sure docker-compose is running in socialNetwork/ directory"
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
    print_info "Starting with quick-test for validation..."
    
    # Run quick-test first for validation
    local tests=("quick-test" "constant-load" "peak-test" "stress-test")
    
    for test in "${tests[@]}"; do
        echo ""
        print_info "========================================="
        print_info "Running ${test}..."
        print_info "========================================="
        echo ""
        
        run_test "${test}"
        
        # Wait between tests to let system recover
        if [ "${test}" = "quick-test" ]; then
            print_info "Quick test completed. Waiting 30 seconds before next test..."
            sleep 30
        elif [ "${test}" != "stress-test" ]; then
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
    detect_base_url
    create_results_dir
    
    case "${TEST_TYPE}" in
        quick-test|constant-load|peak-test|stress-test|endurance-test)
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
            echo "  quick-test     - Quick 20-second validation test (run this first!)"
            echo "  constant-load  - Constant steady load test"
            echo "  peak-test      - Sudden traffic spike test"
            echo "  stress-test    - Gradual ramp-up stress test"
            echo "  endurance-test - Long-duration soak test"
            echo "  all            - Run all tests (quick-test first, then others)"
            echo ""
            echo "Environment variables:"
            echo "  BASE_URL - Target URL (auto-detected if not set)"
            echo "  ENVIRONMENT - Environment type: auto (default), local, or gke"
            echo ""
            echo "Examples:"
            echo "  # Local testing (docker-compose)"
            echo "  ENVIRONMENT=local $0 constant-load"
            echo ""
            echo "  # GKE testing (auto-detect LoadBalancer IP)"
            echo "  ENVIRONMENT=gke $0 constant-load"
            echo ""
            echo "  # Manual URL"
            echo "  BASE_URL=http://1.2.3.4:8080 $0 constant-load"
            exit 1
            ;;
    esac
}

main

