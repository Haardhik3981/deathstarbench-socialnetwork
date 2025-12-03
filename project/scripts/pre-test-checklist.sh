#!/bin/bash

# Pre-Test Checklist Script
# Run this before running k6 tests to ensure everything is ready

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

echo ""
echo "=========================================="
echo "  Pre-Test Checklist"
echo "=========================================="
echo ""

# Step 1: Run verification script
print_section "Step 1: Running Deployment Verification"
echo ""

if [ -f "./scripts/verify-deployment.sh" ]; then
    ./scripts/verify-deployment.sh
    VERIFY_EXIT=$?
    
    if [ $VERIFY_EXIT -ne 0 ]; then
        echo ""
        print_error "Deployment verification failed!"
        print_info "Please fix the issues above before running tests"
        exit 1
    fi
else
    print_error "verify-deployment.sh not found"
    exit 1
fi

echo ""

# Step 2: Check nginx-thrift is accessible
print_section "Step 2: Checking nginx-thrift Accessibility"

# Check if port-forward is running
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    print_success "Port-forward is running on port 8080"
    print_info "You can access nginx-thrift at http://localhost:8080"
else
    print_warn "Port-forward is not running on port 8080"
    echo ""
    print_info "To start port-forward, run in another terminal:"
    echo "  kubectl port-forward svc/nginx-thrift 8080:8080"
    echo ""
    read -p "Do you want to start port-forward now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Starting port-forward in background..."
        kubectl port-forward svc/nginx-thrift 8080:8080 > /dev/null 2>&1 &
        PORT_FORWARD_PID=$!
        sleep 2
        if kill -0 $PORT_FORWARD_PID 2>/dev/null; then
            print_success "Port-forward started (PID: $PORT_FORWARD_PID)"
            print_info "To stop it later: kill $PORT_FORWARD_PID"
        else
            print_error "Failed to start port-forward"
        fi
    fi
fi

echo ""

# Step 3: Test endpoint
print_section "Step 3: Testing nginx-thrift Endpoint"

if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    print_info "Testing endpoint: http://localhost:8080/"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ || echo "000")
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "302" ]; then
        print_success "nginx-thrift is responding (HTTP $HTTP_CODE)"
    elif [ "$HTTP_CODE" = "000" ]; then
        print_error "Cannot connect to nginx-thrift (connection refused)"
        print_info "Check if port-forward is running and nginx-thrift pod is ready"
    else
        print_warn "nginx-thrift returned HTTP $HTTP_CODE"
    fi
else
    print_warn "Skipping endpoint test (port-forward not running)"
fi

echo ""

# Step 4: Check k6 is installed
print_section "Step 4: Checking k6 Installation"

if command -v k6 &> /dev/null; then
    K6_VERSION=$(k6 version | head -n 1)
    print_success "k6 is installed: $K6_VERSION"
else
    print_error "k6 is not installed"
    print_info "Install k6:"
    echo "  macOS: brew install k6"
    echo "  Linux: https://k6.io/docs/getting-started/installation/"
    exit 1
fi

echo ""

# Step 5: Check test files exist
print_section "Step 5: Checking Test Files"

if [ -f "./k6-tests/constant-load.js" ]; then
    print_success "constant-load.js exists"
else
    print_error "constant-load.js not found"
    exit 1
fi

if [ -f "./k6-tests/test-helpers.js" ]; then
    print_success "test-helpers.js exists"
else
    print_error "test-helpers.js not found (required for constant-load.js)"
    exit 1
fi

echo ""

# Final Summary
print_section "Pre-Test Checklist Complete"
echo ""

print_success "All checks passed! You're ready to run k6 tests."
echo ""
print_info "To run the constant load test:"
echo "  k6 run k6-tests/constant-load.js"
echo ""
print_info "Or with custom BASE_URL:"
echo "  BASE_URL=http://localhost:8080 k6 run k6-tests/constant-load.js"
echo ""
print_info "Make sure port-forward is running in another terminal:"
echo "  kubectl port-forward svc/nginx-thrift 8080:8080"
echo ""

