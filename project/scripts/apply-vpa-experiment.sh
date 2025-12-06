#!/bin/bash

# VPA Experiment Helper Script
# Applies VPA experiment configurations and manages VPA recommendations

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

VPA_NAME="user-service-vpa"
DEPLOYMENT_NAME="user-service-deployment"
NAMESPACE="default"
EXPERIMENTS_FILE="kubernetes/autoscaling/user-service-vpa-experiments.yaml"

usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  list                    - List available VPA experiment configurations"
    echo "  apply <experiment>      - Apply a VPA experiment configuration"
    echo "  show-recommendations    - Show current VPA recommendations"
    echo "  apply-recommendations   - Manually apply VPA recommendations to deployment"
    echo "  set-mode <mode>         - Set VPA update mode (Off|Recreate|Initial|Auto)"
    echo "  current                 - Show current VPA configuration"
    echo ""
    echo "Available experiments:"
    echo "  - conservative          (Lower cost, more pods)"
    echo "  - moderate              (Balanced)"
    echo "  - aggressive            (Higher cost, fewer pods, better latency)"
    echo "  - cpu-optimized         (High CPU, moderate memory)"
    echo "  - memory-optimized      (Moderate CPU, high memory)"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 apply conservative"
    echo "  $0 show-recommendations"
    echo "  $0 apply-recommendations"
    echo "  $0 set-mode Recreate"
}

list_experiments() {
    echo -e "${BLUE}Available VPA Experiment Configurations:${NC}"
    echo ""
    if [ -f "$EXPERIMENTS_FILE" ]; then
        grep -A 5 "name: user-service-vpa-" "$EXPERIMENTS_FILE" | grep -E "(name:|experiment:|cost-priority:|maxAllowed:)" | \
        sed 's/.*name: /  - /' | sed 's/.*experiment: /    Experiment: /' | sed 's/.*cost-priority: /    Cost Priority: /' | \
        sed 's/.*maxAllowed:/    Max Resources:/'
    else
        echo -e "${RED}✗${NC} Experiments file not found: $EXPERIMENTS_FILE"
        exit 1
    fi
}

apply_experiment() {
    local experiment=$1
    
    if [ -z "$experiment" ]; then
        echo -e "${RED}Error:${NC} Experiment name required"
        usage
        exit 1
    fi
    
    local vpa_name="user-service-vpa-$experiment"
    
    # Check if experiment exists in file
    if ! grep -q "name: $vpa_name" "$EXPERIMENTS_FILE"; then
        echo -e "${RED}Error:${NC} Experiment '$experiment' not found"
        echo "Available experiments:"
        grep "name: user-service-vpa-" "$EXPERIMENTS_FILE" | sed 's/.*name: user-service-vpa-//' | sed 's/$/ /' | tr -d '\n'
        echo ""
        exit 1
    fi
    
    echo -e "${BLUE}Applying VPA experiment: $experiment${NC}"
    echo ""
    
    # Extract and apply the specific VPA configuration
    # Use awk to extract the specific VPA block (from --- to next --- or end of file)
    awk -v name="$vpa_name" '
        BEGIN { in_block=0; block="" }
        /^---/ {
            if (in_block && block != "") {
                print block
                exit
            }
            block="---\n"
            in_block=0
        }
        /name: / && $0 ~ name { in_block=1 }
        in_block { block=block $0 "\n" }
        END { 
            if (in_block && block != "") {
                print block
            }
        }
    ' "$EXPERIMENTS_FILE" | kubectl apply -f -
    
    # Delete the old VPA if it exists and is different
    if kubectl get vpa "$VPA_NAME" -n "$NAMESPACE" &>/dev/null; then
        if [ "$vpa_name" != "$VPA_NAME" ]; then
            echo "Deleting old VPA: $VPA_NAME"
            kubectl delete vpa "$VPA_NAME" -n "$NAMESPACE" || true
        fi
    fi
    
    echo ""
    echo -e "${GREEN}✓${NC} VPA experiment '$experiment' applied"
    echo ""
    echo "Current VPA configuration:"
    kubectl get vpa "$vpa_name" -n "$NAMESPACE" 2>/dev/null || kubectl get vpa -n "$NAMESPACE" | grep user-service
}

show_recommendations() {
    local vpa_name=$1
    if [ -z "$vpa_name" ]; then
        # Find the active VPA
        vpa_name=$(kubectl get vpa -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.targetRef.name=="'$DEPLOYMENT_NAME'")].metadata.name}' 2>/dev/null | awk '{print $1}')
        if [ -z "$vpa_name" ]; then
            echo -e "${RED}Error:${NC} No VPA found for $DEPLOYMENT_NAME"
            exit 1
        fi
    fi
    
    echo -e "${BLUE}VPA Recommendations for: $vpa_name${NC}"
    echo ""
    
    kubectl describe vpa "$vpa_name" -n "$NAMESPACE" | grep -A 20 "Recommendation:" || {
        echo -e "${YELLOW}⚠${NC} No recommendations available yet"
        echo "   VPA needs time to collect usage data. Run a test to generate load."
    }
}

apply_recommendations() {
    local vpa_name=$1
    if [ -z "$vpa_name" ]; then
        # Find the active VPA
        vpa_name=$(kubectl get vpa -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.targetRef.name=="'$DEPLOYMENT_NAME'")].metadata.name}' 2>/dev/null | awk '{print $1}')
        if [ -z "$vpa_name" ]; then
            echo -e "${RED}Error:${NC} No VPA found for $DEPLOYMENT_NAME"
            exit 1
        fi
    fi
    
    echo -e "${BLUE}Applying VPA recommendations to deployment${NC}"
    echo ""
    
    # Get recommendations
    local cpu_reco=$(kubectl get vpa "$vpa_name" -n "$NAMESPACE" -o jsonpath='{.status.recommendation.containerRecommendations[0].target.cpu}' 2>/dev/null)
    local mem_reco=$(kubectl get vpa "$vpa_name" -n "$NAMESPACE" -o jsonpath='{.status.recommendation.containerRecommendations[0].target.memory}' 2>/dev/null)
    
    if [ -z "$cpu_reco" ] || [ -z "$mem_reco" ]; then
        echo -e "${RED}Error:${NC} No recommendations available"
        echo "   Run a test first to let VPA collect usage data"
        exit 1
    fi
    
    # Convert memory to a more readable format (approximate)
    local mem_mb=$((mem_reco / 1024 / 1024))
    
    echo "Recommendations:"
    echo "  CPU: $cpu_reco"
    echo "  Memory: ${mem_mb}Mi (${mem_reco} bytes)"
    echo ""
    
    read -p "Apply these recommendations to deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Apply recommendations using kubectl patch
    # Note: We'll use the target values as both requests and limits for simplicity
    kubectl patch deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" --type='json' -p="[{
        \"op\": \"replace\",
        \"path\": \"/spec/template/spec/containers/0/resources/requests/cpu\",
        \"value\": \"$cpu_reco\"
    }, {
        \"op\": \"replace\",
        \"path\": \"/spec/template/spec/containers/0/resources/requests/memory\",
        \"value\": \"${mem_mb}Mi\"
    }, {
        \"op\": \"replace\",
        \"path\": \"/spec/template/spec/containers/0/resources/limits/cpu\",
        \"value\": \"$cpu_reco\"
    }, {
        \"op\": \"replace\",
        \"path\": \"/spec/template/spec/containers/0/resources/limits/memory\",
        \"value\": \"${mem_mb}Mi\"
    }]"
    
    echo ""
    echo -e "${GREEN}✓${NC} Recommendations applied. Pods will be recreated with new resources."
}

set_mode() {
    local mode=$1
    local vpa_name=$2
    
    if [ -z "$mode" ]; then
        echo -e "${RED}Error:${NC} Mode required (Off|Recreate|Initial|Auto)"
        exit 1
    fi
    
    if [ -z "$vpa_name" ]; then
        # Find the active VPA
        vpa_name=$(kubectl get vpa -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.targetRef.name=="'$DEPLOYMENT_NAME'")].metadata.name}' 2>/dev/null | awk '{print $1}')
        if [ -z "$vpa_name" ]; then
            echo -e "${RED}Error:${NC} No VPA found for $DEPLOYMENT_NAME"
            exit 1
        fi
    fi
    
    case "$mode" in
        Off|Recreate|Initial|Auto)
            echo -e "${BLUE}Setting VPA mode to: $mode${NC}"
            kubectl patch vpa "$vpa_name" -n "$NAMESPACE" --type='merge' -p="{\"spec\":{\"updatePolicy\":{\"updateMode\":\"$mode\"}}}"
            echo -e "${GREEN}✓${NC} VPA mode updated"
            ;;
        *)
            echo -e "${RED}Error:${NC} Invalid mode: $mode"
            echo "Valid modes: Off, Recreate, Initial, Auto"
            exit 1
            ;;
    esac
}

show_current() {
    local vpa_name=$1
    if [ -z "$vpa_name" ]; then
        # Find the active VPA
        vpa_name=$(kubectl get vpa -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.targetRef.name=="'$DEPLOYMENT_NAME'")].metadata.name}' 2>/dev/null | awk '{print $1}')
        if [ -z "$vpa_name" ]; then
            echo -e "${RED}Error:${NC} No VPA found for $DEPLOYMENT_NAME"
            exit 1
        fi
    fi
    
    echo -e "${BLUE}Current VPA Configuration:${NC}"
    echo ""
    kubectl get vpa "$vpa_name" -n "$NAMESPACE" -o yaml | grep -A 30 "spec:"
}

# Main command handling
case "${1:-}" in
    list)
        list_experiments
        ;;
    apply)
        apply_experiment "$2"
        ;;
    show-recommendations)
        show_recommendations "$2"
        ;;
    apply-recommendations)
        apply_recommendations "$2"
        ;;
    set-mode)
        set_mode "$2" "$3"
        ;;
    current)
        show_current "$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac

