#!/bin/bash

# =============================================================================
# Social Network Load Testing Runner Script
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="cse239fall2025"
BASE_URL="${BASE_URL:-http://localhost:8080}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}"
    echo "=============================================================================="
    echo "$1"
    echo "=============================================================================="
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check k6
    if command -v k6 &> /dev/null; then
        print_success "k6 is installed: $(k6 version)"
    else
        print_error "k6 is not installed"
        echo "Install with: brew install k6"
        exit 1
    fi
    
    # Check kubectl
    if command -v kubectl &> /dev/null; then
        print_success "kubectl is installed"
    else
        print_error "kubectl is not installed"
        exit 1
    fi
    
    # Check if port-forward is needed
    if curl -s --max-time 2 "$BASE_URL" > /dev/null 2>&1; then
        print_success "Application is accessible at $BASE_URL"
    else
        print_warning "Application not accessible at $BASE_URL"
        echo "Make sure to run: kubectl port-forward deployment/nginx-thrift 8080:8080 -n $NAMESPACE"
    fi
}

apply_hpa() {
    print_header "Applying Horizontal Pod Autoscaler"
    kubectl apply -f "$SCRIPT_DIR/hpa-config.yaml" -n $NAMESPACE
    print_success "HPA applied successfully"
    
    echo ""
    echo "Current HPA status:"
    kubectl get hpa -n $NAMESPACE
}

apply_vpa() {
    print_header "Applying Vertical Pod Autoscaler"
    
    # Check if VPA CRD exists
    if kubectl get crd verticalpodautoscalers.autoscaling.k8s.io &> /dev/null; then
        kubectl apply -f "$SCRIPT_DIR/vpa-config.yaml" -n $NAMESPACE
        print_success "VPA applied successfully"
        
        echo ""
        echo "Current VPA status:"
        kubectl get vpa -n $NAMESPACE
    else
        print_warning "VPA CRD not found in cluster"
        echo "VPA controller may not be installed on this cluster."
        echo "Skipping VPA configuration."
    fi
}

run_load_test() {
    print_header "Running Load Test"
    echo "Duration: ~14 minutes"
    echo "Target: Gradual ramp to 100 concurrent users"
    echo ""
    
    cd "$SCRIPT_DIR"
    k6 run --env BASE_URL="$BASE_URL" k6-load-test.js
}

run_stress_test() {
    print_header "Running Stress Test"
    echo "Duration: ~15 minutes"
    echo "Target: Ramp to 600 concurrent users to find breaking point"
    echo ""
    
    cd "$SCRIPT_DIR"
    k6 run --env BASE_URL="$BASE_URL" k6-stress-test.js
}

run_soak_test() {
    print_header "Running Soak Test"
    echo "Duration: ~30 minutes"
    echo "Target: Sustained 75 concurrent users"
    echo ""
    
    cd "$SCRIPT_DIR"
    k6 run --env BASE_URL="$BASE_URL" k6-soak-test.js
}

watch_hpa() {
    print_header "Watching HPA Scaling"
    echo "Press Ctrl+C to stop"
    echo ""
    
    kubectl get hpa -n $NAMESPACE -w
}

watch_pods() {
    print_header "Watching Pod Status"
    echo "Press Ctrl+C to stop"
    echo ""
    
    kubectl get pods -n $NAMESPACE -w
}

show_menu() {
    print_header "Social Network Load Testing Menu"
    echo "1) Check prerequisites"
    echo "2) Apply HPA (Horizontal Pod Autoscaler)"
    echo "3) Apply VPA (Vertical Pod Autoscaler)"
    echo "4) Run Load Test (~14 min)"
    echo "5) Run Stress Test (~15 min)"
    echo "6) Run Soak Test (~30 min)"
    echo "7) Watch HPA scaling"
    echo "8) Watch pod status"
    echo "9) Exit"
    echo ""
}

# Main script
case "$1" in
    prereq)
        check_prerequisites
        ;;
    hpa)
        apply_hpa
        ;;
    vpa)
        apply_vpa
        ;;
    load)
        check_prerequisites
        run_load_test
        ;;
    stress)
        check_prerequisites
        run_stress_test
        ;;
    soak)
        check_prerequisites
        run_soak_test
        ;;
    watch-hpa)
        watch_hpa
        ;;
    watch-pods)
        watch_pods
        ;;
    *)
        # Interactive menu
        while true; do
            show_menu
            read -p "Select option: " choice
            case $choice in
                1) check_prerequisites ;;
                2) apply_hpa ;;
                3) apply_vpa ;;
                4) run_load_test ;;
                5) run_stress_test ;;
                6) run_soak_test ;;
                7) watch_hpa ;;
                8) watch_pods ;;
                9) echo "Goodbye!"; exit 0 ;;
                *) print_error "Invalid option" ;;
            esac
            echo ""
            read -p "Press Enter to continue..."
        done
        ;;
esac

