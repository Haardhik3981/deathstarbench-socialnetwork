#!/bin/bash

# Autoscaling Experiments Runner
#
# WHAT THIS DOES:
# Runs controlled experiments to find the optimal autoscaling configuration
# that maintains <500ms latency while minimizing cost.
#
# EXPERIMENT DESIGN:
# 1. Test different HPA configurations (latency-based vs resource-based)
# 2. Test different VPA configurations (conservative vs aggressive)
# 3. Measure latency, cost, and pod count for each configuration
# 4. Generate comparison data for analysis
#
# USAGE:
#   ./run-autoscaling-experiments.sh [experiment-name]
#   ./run-autoscaling-experiments.sh all

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/autoscaling-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

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

# Check prerequisites
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed."
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null 2>&1; then
        print_error "kubectl is not configured."
        exit 1
    fi
    
    if ! command -v k6 &> /dev/null; then
        print_warn "k6 is not installed. Latency measurements may be limited."
    fi
}

# Create results directory
create_results_dir() {
    mkdir -p "${RESULTS_DIR}"
    print_info "Results will be saved to: ${RESULTS_DIR}"
}

# Get current metrics
collect_metrics() {
    local experiment_name=$1
    local output_file="${RESULTS_DIR}/${experiment_name}_metrics_${TIMESTAMP}.json"
    
    print_info "Collecting metrics for ${experiment_name}..."
    
    # Get pod count
    POD_COUNT=$(kubectl get deployment user-service-deployment -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    
    # Get HPA status
    HPA_STATUS=$(kubectl get hpa -o json 2>/dev/null || echo "{}")
    
    # Get pod resource usage
    POD_METRICS=$(kubectl top pods -l app=user-service 2>/dev/null || echo "[]")
    
    # Get VPA recommendations (if available)
    VPA_RECOMMENDATIONS=$(kubectl get vpa user-service-vpa -o json 2>/dev/null || echo "{}")
    
    # Combine into JSON
    cat > "${output_file}" <<EOF
{
  "experiment": "${experiment_name}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pod_count": ${POD_COUNT},
  "hpa_status": ${HPA_STATUS},
  "pod_metrics": ${POD_METRICS},
  "vpa_recommendations": ${VPA_RECOMMENDATIONS}
}
EOF
    
    print_info "Metrics saved to: ${output_file}"
}

# Run latency test
run_latency_test() {
    local experiment_name=$1
    local duration="${2:-5m}"  # Default 5 minutes
    
    print_info "Running latency test for ${experiment_name}..."
    
    # Get endpoint
    ENDPOINT=$(./get-endpoint.sh 2>/dev/null || echo "http://localhost:8080")
    
    # Run k6 constant load test
    if command -v k6 &> /dev/null; then
        BASE_URL="${ENDPOINT}" k6 run \
            --out "json=${RESULTS_DIR}/${experiment_name}_k6_${TIMESTAMP}.json" \
            --duration "${duration}" \
            --vus 100 \
            "${PROJECT_ROOT}/k6-tests/constant-load.js" || true
    else
        print_warn "k6 not available, skipping latency test"
    fi
}

# Apply HPA configuration
apply_hpa_config() {
    local config_name=$1
    print_info "Applying HPA configuration: ${config_name}"
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/${config_name}"
    
    # Wait for HPA to be ready
    sleep 5
    kubectl get hpa
}

# Apply VPA configuration
apply_vpa_config() {
    local config_name=$1
    print_info "Applying VPA configuration: ${config_name}"
    kubectl apply -f "${PROJECT_ROOT}/kubernetes/autoscaling/${config_name}"
    
    # Wait for VPA to be ready
    sleep 5
    kubectl get vpa
}

# Run a single experiment
run_experiment() {
    local experiment_name=$1
    local hpa_config=$2
    local vpa_config=$3
    
    print_experiment "========================================="
    print_experiment "Running Experiment: ${experiment_name}"
    print_experiment "========================================="
    echo ""
    
    # Apply configurations
    if [ -n "${hpa_config}" ]; then
        apply_hpa_config "${hpa_config}"
    fi
    
    if [ -n "${vpa_config}" ]; then
        apply_vpa_config "${vpa_config}"
    fi
    
    # Wait for stabilization
    print_info "Waiting 2 minutes for system to stabilize..."
    sleep 120
    
    # Collect baseline metrics
    collect_metrics "${experiment_name}_baseline"
    
    # Run latency test
    run_latency_test "${experiment_name}" "5m"
    
    # Collect final metrics
    collect_metrics "${experiment_name}_final"
    
    # Wait before next experiment
    print_info "Waiting 1 minute before next experiment..."
    sleep 60
}

# Main experiment runner
main() {
    local experiment="${1:-all}"
    
    check_prerequisites
    create_results_dir
    
    print_info "Starting autoscaling experiments..."
    print_info "Target: Maintain <500ms latency while minimizing cost"
    echo ""
    
    case "${experiment}" in
        latency-hpa)
            run_experiment "latency-hpa" "user-service-hpa-latency.yaml" ""
            ;;
        resource-hpa)
            run_experiment "resource-hpa" "user-service-hpa-resource.yaml" ""
            ;;
        vpa-conservative)
            run_experiment "vpa-conservative" "" "user-service-vpa-experiments.yaml"
            # Note: VPA experiments need to be applied individually
            ;;
        all)
            print_info "Running all experiments..."
            
            # Experiment 1: Latency-based HPA
            run_experiment "latency-hpa" "user-service-hpa-latency.yaml" ""
            
            # Experiment 2: Resource-based HPA
            run_experiment "resource-hpa" "user-service-hpa-resource.yaml" ""
            
            # Experiment 3: Combined (latency HPA + moderate VPA)
            run_experiment "combined-moderate" "user-service-hpa-latency.yaml" "user-service-vpa-experiments.yaml"
            
            print_info "All experiments complete!"
            print_info "Results saved to: ${RESULTS_DIR}"
            print_info "Analyze results to find optimal configuration"
            ;;
        *)
            print_error "Unknown experiment: ${experiment}"
            echo ""
            echo "Available experiments:"
            echo "  latency-hpa      - Latency-based HPA only"
            echo "  resource-hpa     - Resource-based HPA only"
            echo "  vpa-conservative - VPA conservative configuration"
            echo "  all              - Run all experiments"
            exit 1
            ;;
    esac
}

main "$@"

