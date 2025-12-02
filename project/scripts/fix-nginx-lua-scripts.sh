#!/bin/bash

# Fix nginx-lua-scripts ConfigMap - properly include all files with subdirectories
# This script creates the ConfigMap with all Lua script files preserving directory structure

set -e

# Colors
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

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"
LUA_SCRIPTS_DIR="${DSB_ROOT}/nginx-web-server/lua-scripts"

print_section "Fixing nginx-lua-scripts ConfigMap"

# Verify source exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    print_error "Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
    print_error "Expected DeathStarBench source at: ${DSB_ROOT}"
    exit 1
fi

print_info "Source directory: ${LUA_SCRIPTS_DIR}"

# Count files
FILE_COUNT=$(find "${LUA_SCRIPTS_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')
print_info "Found $FILE_COUNT files in source directory"

if [ "$FILE_COUNT" -eq 0 ]; then
    print_error "No files found in Lua scripts directory!"
    exit 1
fi

# Delete existing ConfigMap
print_info ""
print_info "Deleting existing ConfigMap (if any)..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && print_info "✓ Deleted" || print_warn "ConfigMap didn't exist"

# Create ConfigMap by explicitly adding each file with its relative path
# This preserves the directory structure (api/, wrk2-api/, etc.)
print_info ""
print_info "Creating ConfigMap with all files (preserving directory structure)..."

cd "${LUA_SCRIPTS_DIR}"

# Create a temporary directory to build the ConfigMap
TEMP_DIR=$(mktemp -d)

# Copy all files maintaining directory structure
print_info "Copying files to temporary directory..."
find . -type f | while read -r file; do
    # Remove leading ./
    clean_path=$(echo "$file" | sed 's|^\./||')
    # Create directory structure in temp dir
    mkdir -p "$(dirname "${TEMP_DIR}/${clean_path}")"
    # Copy file
    cp "$file" "${TEMP_DIR}/${clean_path}"
done

# Now create ConfigMap from temp directory
FILE_COUNT_FINAL=$(find "${TEMP_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')
print_info "Adding $FILE_COUNT_FINAL files to ConfigMap..."

# Create ConfigMap from the temp directory (kubectl handles this better)
cd "${TEMP_DIR}"
kubectl create configmap nginx-lua-scripts --from-file=. >/dev/null 2>&1 || {
    # Fallback: create with explicit files
    print_warn "Directory method failed, trying explicit file method..."
    cd "${LUA_SCRIPTS_DIR}"
    
    # Build command with all files
    FILE_LIST=$(find . -type f)
    KUBECTL_CMD="kubectl create configmap nginx-lua-scripts"
    
    for file in $FILE_LIST; do
        clean_path=$(echo "$file" | sed 's|^\./||')
        KUBECTL_CMD="${KUBECTL_CMD} --from-file=${clean_path}=${file}"
    done
    
    # Execute command
    eval "$KUBECTL_CMD" || {
        print_error "Failed to create ConfigMap"
        rm -rf "${TEMP_DIR}"
        exit 1
    }
}

# Cleanup
cd "${PROJECT_ROOT}"
rm -rf "${TEMP_DIR}"

# Verify - check if ConfigMap exists and has data
sleep 2
print_info ""
print_info "Verifying ConfigMap..."

if kubectl get configmap nginx-lua-scripts >/dev/null 2>&1; then
    # Count keys in the data section
    DATA_KEYS=$(kubectl get configmap nginx-lua-scripts -o jsonpath='{range .data}{@}{"\n"}{end}' 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$DATA_KEYS" -gt 0 ]; then
        print_info "✓ ConfigMap created successfully with $DATA_KEYS files"
        
        # Show first few file names
        print_info ""
        print_info "Sample files in ConfigMap:"
        kubectl get configmap nginx-lua-scripts -o jsonpath='{range .data}{@}{"\n"}{end}' 2>/dev/null | head -5 | sed 's/^/  /'
    else
        print_warn "ConfigMap exists but may be empty"
    fi
else
    print_error "ConfigMap was not created!"
    exit 1
fi

print_info ""
print_info "✓ nginx-lua-scripts ConfigMap fix complete!"
