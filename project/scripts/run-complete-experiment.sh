#!/bin/bash

# Complete Experiment Runner
#
# WHAT THIS DOES:
# Runs a complete experiment: applies autoscaling configuration, runs k6 test,
# collects all metrics, and saves results for analysis.
#
# USAGE:
#   ./run-complete-experiment.sh [experiment-name] [k6-test-type]
#
# EXAMPLES:
#   ./run-complete-experiment.sh latency-hpa constant-load
#   ./run-complete-experiment.sh latency-hpa-moderate-vpa stress-test

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/experiment-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

EXPERIMENT_NAME="${1:-default-experiment}"
K6_TEST_TYPE="${2:-constant-load}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

print_experiment() {
    echo -e "${BLUE}[EXPERIMENT]${NC} $1"
}

# Create results directory
create_results_dir() {
    mkdir -p "${RESULTS_DIR}/${EXPERIMENT_NAME}"
    print_info "Results will be saved to: ${RESULTS_DIR}/${EXPERIMENT_NAME}"
}

# Apply HPA configuration
apply_hpa() {
    local hpa_type=$1
    
    print_info "Applying HPA configuration: ${hpa_type}"
    
    case "${hpa_type}" in
        latency|latency-based)
            kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/user-service-hpa-latency.yaml"
            HPA_NAME="user-service-hpa-latency"
            ;;
        resource|resource-based)
            kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/user-service-hpa-resource.yaml"
            HPA_NAME="user-service-hpa-resource"
            ;;
        none)
            print_info "No HPA configuration specified"
            kubectl delete hpa --all 2>/dev/null || true
            HPA_NAME="none"
            ;;
        *)
            print_error "Unknown HPA type: ${hpa_type}"
            exit 1
            ;;
    esac
    
    echo "${HPA_NAME}"
}

# Apply VPA configuration
apply_vpa() {
    local vpa_type=$1
    
    if [ -z "${vpa_type}" ] || [ "${vpa_type}" = "none" ]; then
        print_info "No VPA configuration specified"
        kubectl delete vpa --all 2>/dev/null || true
        return
    fi
    
    print_info "Applying VPA configuration: ${vpa_type}"
    
    # VPA configurations are in the experiments file
    # For now, we'll apply the file and user can manually delete unwanted VPAs
    # Or we could create separate files for each VPA config
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/user-service-vpa-experiments.yaml"
    
    print_warn "Multiple VPAs applied. Please delete unwanted ones:"
    print_info "  kubectl delete vpa user-service-vpa-<unwanted-config>"
}

# Collect baseline metrics (before test)
collect_baseline_metrics() {
    local output_file="${RESULTS_DIR}/${EXPERIMENT_NAME}/baseline_${TIMESTAMP}.json"
    
    print_info "Collecting baseline metrics..."
    
    POD_COUNT=$(kubectl get deployment user-service-deployment -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    HPA_STATUS=$(kubectl get hpa -o json 2>/dev/null || echo "{}")
    POD_LIST=$(kubectl get pods -l app=user-service -o json 2>/dev/null || echo "[]")
    
    cat > "${output_file}" <<EOF
{
  "experiment": "${EXPERIMENT_NAME}",
  "phase": "baseline",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pod_count": ${POD_COUNT},
  "hpa_status": ${HPA_STATUS},
  "pods": ${POD_LIST}
}
EOF
    
    print_info "Baseline metrics saved to: ${output_file}"
}

# Collect metrics during/after test
collect_test_metrics() {
    local phase=$1  # "during" or "after"
    local output_file="${RESULTS_DIR}/${EXPERIMENT_NAME}/${phase}_${TIMESTAMP}.json"
    
    print_info "Collecting ${phase} test metrics..."
    
    POD_COUNT=$(kubectl get deployment user-service-deployment -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    HPA_STATUS=$(kubectl get hpa -o json 2>/dev/null || echo "{}")
    POD_METRICS=$(kubectl top pods -l app=user-service --no-headers 2>/dev/null | awk '{print "{\"name\":\""$1"\",\"cpu\":\""$2"\",\"memory\":\""$3"\"}"}' | jq -s '.' || echo "[]")
    VPA_STATUS=$(kubectl get vpa -o json 2>/dev/null || echo "{}")
    
    cat > "${output_file}" <<EOF
{
  "experiment": "${EXPERIMENT_NAME}",
  "phase": "${phase}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pod_count": ${POD_COUNT},
  "hpa_status": ${HPA_STATUS},
  "pod_metrics": ${POD_METRICS},
  "vpa_status": ${VPA_STATUS}
}
EOF
    
    print_info "Test metrics saved to: ${output_file}"
}

# Run k6 test
run_k6_test() {
    print_info "Running k6 test: ${K6_TEST_TYPE}"
    
    # Get endpoint
    ENDPOINT=$(./scripts/get-endpoint.sh 2>/dev/null || echo "http://localhost:8080")
    
    # Create k6 results directory
    mkdir -p "${RESULTS_DIR}/${EXPERIMENT_NAME}/k6"
    
    # Run k6 test
    if command -v k6 &> /dev/null; then
        BASE_URL="${ENDPOINT}" k6 run \
            --out "json=${RESULTS_DIR}/${EXPERIMENT_NAME}/k6/${K6_TEST_TYPE}_${TIMESTAMP}.json" \
            --summary-export="${RESULTS_DIR}/${EXPERIMENT_NAME}/k6/${K6_TEST_TYPE}_${TIMESTAMP}_summary.txt" \
            "${PROJECT_ROOT}/k6-tests/${K6_TEST_TYPE}.js" || true
        
        print_info "k6 test results saved to: ${RESULTS_DIR}/${EXPERIMENT_NAME}/k6/"
    else
        print_warn "k6 not installed, skipping load test"
    fi
}

# Generate summary report
generate_summary() {
    local summary_file="${RESULTS_DIR}/${EXPERIMENT_NAME}/summary_${TIMESTAMP}.txt"
    
    print_info "Generating summary report..."
    
    cat > "${summary_file}" <<EOF
========================================
Experiment Summary: ${EXPERIMENT_NAME}
========================================

Test Configuration:
  - HPA: ${HPA_NAME}
  - VPA: ${VPA_TYPE:-none}
  - k6 Test: ${K6_TEST_TYPE}
  - Timestamp: ${TIMESTAMP}

Pod Count:
  - Initial: $(kubectl get deployment user-service-deployment -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "N/A")
  - Current: $(kubectl get deployment user-service-deployment -o jsonpath='{.status.replicas}' 2>/dev/null || echo "N/A")

HPA Status:
$(kubectl get hpa -o wide 2>/dev/null || echo "No HPA found")

VPA Status:
$(kubectl get vpa -o wide 2>/dev/null || echo "No VPA found")

Resource Usage:
$(kubectl top pods -l app=user-service 2>/dev/null || echo "Metrics not available")

k6 Results:
  - Location: ${RESULTS_DIR}/${EXPERIMENT_NAME}/k6/

Next Steps:
  1. Review k6 results: cat ${RESULTS_DIR}/${EXPERIMENT_NAME}/k6/${K6_TEST_TYPE}_${TIMESTAMP}_summary.txt
  2. Check metrics: cat ${RESULTS_DIR}/${EXPERIMENT_NAME}/*.json
  3. Compare with other experiments
EOF
    
    print_info "Summary saved to: ${summary_file}"
    cat "${summary_file}"
}

# Main experiment flow
main() {
    print_experiment "========================================="
    print_experiment "Running Experiment: ${EXPERIMENT_NAME}"
    print_experiment "k6 Test: ${K6_TEST_TYPE}"
    print_experiment "========================================="
    echo ""
    
    # Parse experiment name for HPA/VPA types
    # Format: "latency-hpa-moderate-vpa" or "resource-hpa" or "latency-hpa"
    if [[ "${EXPERIMENT_NAME}" == *"latency"* ]]; then
        HPA_TYPE="latency"
    elif [[ "${EXPERIMENT_NAME}" == *"resource"* ]]; then
        HPA_TYPE="resource"
    else
        HPA_TYPE="latency"  # Default
    fi
    
    if [[ "${EXPERIMENT_NAME}" == *"conservative"* ]]; then
        VPA_TYPE="conservative"
    elif [[ "${EXPERIMENT_NAME}" == *"moderate"* ]]; then
        VPA_TYPE="moderate"
    elif [[ "${EXPERIMENT_NAME}" == *"aggressive"* ]]; then
        VPA_TYPE="aggressive"
    else
        VPA_TYPE="none"
    fi
    
    create_results_dir
    
    # Apply configurations
    HPA_NAME=$(apply_hpa "${HPA_TYPE}")
    apply_vpa "${VPA_TYPE}"
    
    # Wait for stabilization
    print_info "Waiting 2 minutes for system to stabilize..."
    sleep 120
    
    # Collect baseline
    collect_baseline_metrics
    
    # Run k6 test (this will take time)
    print_info "Starting k6 load test..."
    run_k6_test
    
    # Collect metrics after test
    collect_test_metrics "after"
    
    # Generate summary
    generate_summary
    
    print_info "Experiment complete!"
    print_info "Results saved to: ${RESULTS_DIR}/${EXPERIMENT_NAME}/"
}

main

