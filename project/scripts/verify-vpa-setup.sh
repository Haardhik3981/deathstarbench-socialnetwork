#!/bin/bash

# VPA Setup Verification Script
# Verifies that VPA is properly configured and ready for experiments

set -e

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VPA Setup Verification"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if VPA CRD exists
echo "1. Checking VPA API Resources..."
if kubectl api-resources | grep -q "verticalpodautoscalers"; then
    echo -e "${GREEN}✓${NC} VPA API resource is available"
else
    echo -e "${RED}✗${NC} VPA API resource not found. VPA may not be installed."
    echo "   Install VPA: https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler"
    exit 1
fi

# Check VPA components (if installed)
echo ""
echo "2. Checking VPA Components..."
VPA_COMPONENTS=$(kubectl get pods --all-namespaces -l app=vpa-recommender 2>/dev/null | wc -l)
if [ "$VPA_COMPONENTS" -gt 1 ]; then
    echo -e "${GREEN}✓${NC} VPA components are running"
    kubectl get pods --all-namespaces -l app=vpa-recommender 2>/dev/null | grep -v NAME
else
    echo -e "${YELLOW}⚠${NC} VPA components not found in standard locations"
    echo "   Note: VPA may be installed differently or using 'Off' mode only"
fi

# Check current VPA configuration
echo ""
echo "3. Checking VPA Configuration..."
VPA_COUNT=$(kubectl get vpa -n default 2>/dev/null | grep -v NAME | wc -l)
if [ "$VPA_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $VPA_COUNT VPA(s) in default namespace:"
    kubectl get vpa -n default
    echo ""
    
    # Check each VPA
    for vpa in $(kubectl get vpa -n default -o jsonpath='{.items[*].metadata.name}'); do
        echo "   VPA: $vpa"
        MODE=$(kubectl get vpa $vpa -n default -o jsonpath='{.spec.updatePolicy.updateMode}' 2>/dev/null || echo "Unknown")
        TARGET=$(kubectl get vpa $vpa -n default -o jsonpath='{.spec.targetRef.name}' 2>/dev/null || echo "Unknown")
        echo "     - Mode: $MODE"
        echo "     - Target: $TARGET"
        
        # Check if recommendations are available
        RECO=$(kubectl get vpa $vpa -n default -o jsonpath='{.status.recommendation}' 2>/dev/null)
        if [ -n "$RECO" ] && [ "$RECO" != "null" ]; then
            echo -e "     - ${GREEN}✓${NC} Recommendations available"
            CPU=$(kubectl get vpa $vpa -n default -o jsonpath='{.status.recommendation.containerRecommendations[0].target.cpu}' 2>/dev/null)
            MEM=$(kubectl get vpa $vpa -n default -o jsonpath='{.status.recommendation.containerRecommendations[0].target.memory}' 2>/dev/null)
            echo "       CPU: $CPU"
            echo "       Memory: $MEM"
        else
            echo -e "     - ${YELLOW}⚠${NC} No recommendations yet (VPA needs time to collect data)"
        fi
        echo ""
    done
else
    echo -e "${RED}✗${NC} No VPA found in default namespace"
    echo "   Apply VPA: kubectl apply -f kubernetes/autoscaling/user-service-vpa.yaml"
    exit 1
fi

# Check target deployment
echo "4. Checking Target Deployment..."
TARGET_DEPLOYMENT=$(kubectl get vpa user-service-vpa -n default -o jsonpath='{.spec.targetRef.name}' 2>/dev/null || echo "")
if [ -n "$TARGET_DEPLOYMENT" ]; then
    if kubectl get deployment $TARGET_DEPLOYMENT -n default &>/dev/null; then
        echo -e "${GREEN}✓${NC} Target deployment '$TARGET_DEPLOYMENT' exists"
        
        # Check current resources
        echo "   Current resource configuration:"
        kubectl get deployment $TARGET_DEPLOYMENT -n default -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.' 2>/dev/null || echo "   (Unable to parse resources)"
    else
        echo -e "${RED}✗${NC} Target deployment '$TARGET_DEPLOYMENT' not found"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC} Could not determine target deployment"
fi

# Check for HPA conflicts
echo ""
echo "5. Checking for HPA Conflicts..."
HPA_COUNT=$(kubectl get hpa -n default 2>/dev/null | grep -v NAME | wc -l)
if [ "$HPA_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} Found $HPA_COUNT HPA(s) in default namespace:"
    kubectl get hpa -n default
    echo ""
    echo "   IMPORTANT: VPA and HPA can conflict if both scale on CPU/memory!"
    echo "   Best practice:"
    echo "     - Use VPA for resource requests/limits (vertical scaling)"
    echo "     - Use HPA for custom metrics (horizontal scaling)"
    echo "     - Or use VPA in 'Off' mode for recommendations only"
else
    echo -e "${GREEN}✓${NC} No HPA found (no conflicts)"
fi

# Check VPA mode
echo ""
echo "6. Checking VPA Update Mode..."
VPA_MODE=$(kubectl get vpa user-service-vpa -n default -o jsonpath='{.spec.updatePolicy.updateMode}' 2>/dev/null || echo "Unknown")
case "$VPA_MODE" in
    "Off")
        echo -e "${YELLOW}⚠${NC} VPA is in 'Off' mode (recommendations only)"
        echo "   For experiments, you have two options:"
        echo "   1. Manually apply recommendations (update deployment resources)"
        echo "   2. Switch to 'Recreate' mode (VPA will automatically update pods)"
        echo ""
        echo "   To switch to Recreate mode:"
        echo "   kubectl patch vpa user-service-vpa -n default --type='merge' -p='{\"spec\":{\"updatePolicy\":{\"updateMode\":\"Recreate\"}}}'"
        ;;
    "Recreate")
        echo -e "${GREEN}✓${NC} VPA is in 'Recreate' mode (will automatically update pods)"
        ;;
    "Auto")
        echo -e "${GREEN}✓${NC} VPA is in 'Auto' mode (requires VPA admission controller)"
        ;;
    "Initial")
        echo -e "${YELLOW}⚠${NC} VPA is in 'Initial' mode (only sets resources on pod creation)"
        ;;
    *)
        echo -e "${YELLOW}⚠${NC} VPA mode: $VPA_MODE"
        ;;
esac

# Check experiment configurations
echo ""
echo "7. Checking Experiment Configurations..."
if [ -f "kubernetes/autoscaling/user-service-vpa-experiments.yaml" ]; then
    echo -e "${GREEN}✓${NC} Experiment configurations file exists"
    EXP_COUNT=$(grep -c "name: user-service-vpa-" kubernetes/autoscaling/user-service-vpa-experiments.yaml 2>/dev/null || echo "0")
    echo "   Found $EXP_COUNT experiment configurations:"
    grep "name: user-service-vpa-" kubernetes/autoscaling/user-service-vpa-experiments.yaml | sed 's/.*name: /     - /'
else
    echo -e "${YELLOW}⚠${NC} Experiment configurations file not found"
fi

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Determine readiness
READY=true
ISSUES=()

if [ "$VPA_COUNT" -eq 0 ]; then
    READY=false
    ISSUES+=("No VPA configured")
fi

if [ "$VPA_MODE" = "Off" ]; then
    echo -e "${YELLOW}⚠${NC} VPA is in 'Off' mode - recommendations only"
    echo "   You'll need to manually apply recommendations for experiments"
    echo ""
fi

if [ "$READY" = true ]; then
    echo -e "${GREEN}✓${NC} VPA is configured and ready for experiments"
    echo ""
    echo "Next steps:"
    echo "1. Run a test to generate load and let VPA collect data"
    echo "2. Check recommendations: kubectl describe vpa user-service-vpa -n default"
    echo "3. Apply a VPA experiment configuration:"
    echo "   kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml"
    echo "   kubectl delete vpa user-service-vpa -n default"
    echo "   kubectl apply -f kubernetes/autoscaling/user-service-vpa-experiments.yaml"
    echo "4. Or manually apply recommendations to deployment"
else
    echo -e "${RED}✗${NC} VPA setup incomplete"
    for issue in "${ISSUES[@]}"; do
        echo "   - $issue"
    done
fi

echo ""

