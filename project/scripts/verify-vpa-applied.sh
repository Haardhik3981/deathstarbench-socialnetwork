#!/bin/bash

# Quick script to verify which VPA is currently applied

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VPA Status Check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# List all VPAs
VPAS=$(kubectl get vpa -n default 2>/dev/null | grep -v NAME | awk '{print $1}')

if [ -z "$VPAS" ]; then
    echo -e "${YELLOW}⚠${NC} No VPA found in default namespace"
    exit 1
fi

for vpa in $VPAS; do
    echo -e "${BLUE}VPA: $vpa${NC}"
    
    # Get mode
    MODE=$(kubectl get vpa $vpa -n default -o jsonpath='{.spec.updatePolicy.updateMode}' 2>/dev/null || echo "Unknown")
    echo "  Mode: $MODE"
    
    # Get target
    TARGET=$(kubectl get vpa $vpa -n default -o jsonpath='{.spec.targetRef.name}' 2>/dev/null || echo "Unknown")
    echo "  Target: $TARGET"
    
    # Get resource limits
    echo "  Resource Limits:"
    MIN_CPU=$(kubectl get vpa $vpa -n default -o jsonpath='{.spec.resourcePolicy.containerPolicies[0].minAllowed.cpu}' 2>/dev/null || echo "N/A")
    MIN_MEM=$(kubectl get vpa $vpa -n default -o jsonpath='{.spec.resourcePolicy.containerPolicies[0].minAllowed.memory}' 2>/dev/null || echo "N/A")
    MAX_CPU=$(kubectl get vpa $vpa -n default -o jsonpath='{.spec.resourcePolicy.containerPolicies[0].maxAllowed.cpu}' 2>/dev/null || echo "N/A")
    MAX_MEM=$(kubectl get vpa $vpa -n default -o jsonpath='{.spec.resourcePolicy.containerPolicies[0].maxAllowed.memory}' 2>/dev/null || echo "N/A")
    
    echo "    Min: CPU=$MIN_CPU, Memory=$MIN_MEM"
    echo "    Max: CPU=$MAX_CPU, Memory=$MAX_MEM"
    
    # Get recommendations if available
    CPU_RECO=$(kubectl get vpa $vpa -n default -o jsonpath='{.status.recommendation.containerRecommendations[0].target.cpu}' 2>/dev/null || echo "")
    MEM_RECO=$(kubectl get vpa $vpa -n default -o jsonpath='{.status.recommendation.containerRecommendations[0].target.memory}' 2>/dev/null || echo "")
    
    if [ -n "$CPU_RECO" ] && [ "$CPU_RECO" != "null" ]; then
        echo "  Current Recommendations:"
        echo "    CPU: $CPU_RECO"
        echo "    Memory: $MEM_RECO bytes"
    else
        echo "  Recommendations: Not available yet (VPA needs usage data)"
    fi
    
    # Check if it's an experiment
    EXP=$(kubectl get vpa $vpa -n default -o jsonpath='{.metadata.labels.experiment}' 2>/dev/null || echo "")
    if [ -n "$EXP" ]; then
        echo -e "  ${GREEN}✓${NC} Experiment: $EXP"
    fi
    
    echo ""
done

# Check deployment resources
echo "═══════════════════════════════════════════════════════════════"
echo "  Current Deployment Resources"
echo "═══════════════════════════════════════════════════════════════"
echo ""

TARGET_DEPLOYMENT=$(kubectl get vpa -n default -o jsonpath='{.items[0].spec.targetRef.name}' 2>/dev/null || echo "user-service-deployment")
if kubectl get deployment $TARGET_DEPLOYMENT -n default &>/dev/null; then
    echo "Deployment: $TARGET_DEPLOYMENT"
    kubectl get deployment $TARGET_DEPLOYMENT -n default -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.' 2>/dev/null || echo "  (Unable to parse)"
else
    echo -e "${YELLOW}⚠${NC} Deployment not found: $TARGET_DEPLOYMENT"
fi

echo ""

