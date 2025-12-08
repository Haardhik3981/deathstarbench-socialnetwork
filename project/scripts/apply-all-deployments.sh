#!/bin/bash

# Apply all deployment YAML files to the cluster
# This script handles the kubectl apply issue with wildcards

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOYMENTS_DIR="$PROJECT_DIR/kubernetes/deployments"

print_info "Applying all deployment files from $DEPLOYMENTS_DIR"
echo ""

# Apply each YAML file individually
# This avoids the kubectl wildcard issue
APPLIED=0
FAILED=0

for file in "$DEPLOYMENTS_DIR"/*.yaml; do
    # Skip backup files
    if [[ "$file" == *.backup ]]; then
        continue
    fi
    
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        print_info "Applying $filename..."
        
        if kubectl apply -f "$file" 2>&1 | grep -qE "(configured|created|unchanged)"; then
            ((APPLIED++))
        else
            print_error "Failed to apply $filename"
            ((FAILED++))
        fi
    fi
done

echo ""
if [ $FAILED -eq 0 ]; then
    print_info "✓ Successfully applied $APPLIED deployment files"
else
    print_error "✗ Applied $APPLIED files, $FAILED failed"
    exit 1
fi

