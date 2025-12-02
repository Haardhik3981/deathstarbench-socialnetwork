#!/bin/bash

# Script to Create All Required ConfigMaps for DeathStarBench Deployment
#
# WHAT THIS DOES:
# This script reads files from the DeathStarBench source directory and creates
# all necessary Kubernetes ConfigMaps for the nginx-thrift gateway.
#
# KEY CONCEPTS:
# - ConfigMaps: Store configuration files and data as Kubernetes resources
# - Allows mounting files into pods without rebuilding images
# - Required for nginx-thrift to work (needs Lua scripts, pages, configs)
#
# PREREQUISITES:
# - kubectl configured and connected to your cluster
# - DeathStarBench source at: ../../socialNetwork
# - All required directories exist

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"

# Verify DeathStarBench source exists
if [ ! -d "${DSB_ROOT}" ]; then
    print_error "DeathStarBench source not found at: ${DSB_ROOT}"
    print_error "Expected directory structure:"
    print_error "  deathstarbench-socialnetwork/"
    print_error "    ├── project/  (current directory)"
    print_error "    └── socialNetwork/  (expected here)"
    exit 1
fi

print_info "Found DeathStarBench source at: ${DSB_ROOT}"

# Verify required directories exist
REQUIRED_DIRS=(
    "${DSB_ROOT}/config"
    "${DSB_ROOT}/nginx-web-server/conf"
    "${DSB_ROOT}/nginx-web-server/lua-scripts"
    "${DSB_ROOT}/nginx-web-server/pages"
    "${DSB_ROOT}/gen-lua"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "${dir}" ]; then
        print_error "Required directory not found: ${dir}"
        exit 1
    fi
done

print_info "All required directories found!"

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Function to create ConfigMap from directory
create_configmap_from_dir() {
    local cm_name=$1
    local source_dir=$2
    local description=$3
    
    print_step "Creating ConfigMap: ${cm_name}"
    print_info "  Source: ${source_dir}"
    
    if [ ! -d "${source_dir}" ]; then
        print_error "Directory not found: ${source_dir}"
        return 1
    fi
    
    # Check if ConfigMap already exists
    if kubectl get configmap "${cm_name}" &>/dev/null; then
        print_warn "ConfigMap ${cm_name} already exists. Updating..."
        kubectl delete configmap "${cm_name}"
    fi
    
    # Create ConfigMap from directory
    kubectl create configmap "${cm_name}" \
        --from-file="${source_dir}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_info "  ✓ Created/Updated: ${cm_name}"
}

# Function to create ConfigMap from single file
create_configmap_from_file() {
    local cm_name=$1
    local file_key=$2
    local source_file=$3
    
    print_step "Adding to ConfigMap: ${cm_name}"
    print_info "  Key: ${file_key}"
    print_info "  File: ${source_file}"
    
    if [ ! -f "${source_file}" ]; then
        print_error "File not found: ${source_file}"
        return 1
    fi
    
    # Check if ConfigMap exists
    if kubectl get configmap "${cm_name}" &>/dev/null; then
        # Add to existing ConfigMap
        kubectl create configmap "${cm_name}" \
            --from-file="${file_key}=${source_file}" \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        # Create new ConfigMap
        kubectl create configmap "${cm_name}" \
            --from-file="${file_key}=${source_file}"
    fi
    
    print_info "  ✓ Added ${file_key} to ${cm_name}"
}

# Step 1: Create the main deathstarbench-config ConfigMap
print_step "=== Step 1: Creating main configuration ConfigMap ==="

# Start with service-config.json
create_configmap_from_file \
    "deathstarbench-config" \
    "service-config.json" \
    "${DSB_ROOT}/config/service-config.json"

# Add jaeger-config.yml
create_configmap_from_file \
    "deathstarbench-config" \
    "jaeger-config.yml" \
    "${DSB_ROOT}/config/jaeger-config.yml"

# Add nginx.conf
create_configmap_from_file \
    "deathstarbench-config" \
    "nginx.conf" \
    "${DSB_ROOT}/nginx-web-server/conf/nginx.conf"

# Add jaeger-config.json (for nginx)
create_configmap_from_file \
    "deathstarbench-config" \
    "jaeger-config.json" \
    "${DSB_ROOT}/nginx-web-server/jaeger-config.json"

# Add optional config files if they exist
if [ -f "${DSB_ROOT}/config/mongod.conf" ]; then
    create_configmap_from_file \
        "deathstarbench-config" \
        "mongod.conf" \
        "${DSB_ROOT}/config/mongod.conf"
fi

if [ -f "${DSB_ROOT}/config/redis.conf" ]; then
    create_configmap_from_file \
        "deathstarbench-config" \
        "redis.conf" \
        "${DSB_ROOT}/config/redis.conf"
fi

# Step 2: Create Lua scripts ConfigMap
print_step "=== Step 2: Creating Lua scripts ConfigMap ==="
create_configmap_from_dir \
    "nginx-lua-scripts" \
    "${DSB_ROOT}/nginx-web-server/lua-scripts" \
    "Lua scripts for nginx-thrift API handlers"

# Step 3: Create pages ConfigMap (HTML/JS/CSS)
print_step "=== Step 3: Creating pages ConfigMap ==="
create_configmap_from_dir \
    "nginx-pages" \
    "${DSB_ROOT}/nginx-web-server/pages" \
    "HTML pages, JavaScript, and CSS for the web interface"

# Step 4: Create generated Lua files ConfigMap (Thrift-generated)
print_step "=== Step 4: Creating generated Lua files ConfigMap ==="
create_configmap_from_dir \
    "nginx-gen-lua" \
    "${DSB_ROOT}/gen-lua" \
    "Generated Lua files from Thrift definitions"

# Summary
echo ""
echo "=========================================="
print_info "CONFIGMAP CREATION COMPLETE!"
echo "=========================================="
echo ""
print_info "Created ConfigMaps:"
echo "  ✓ deathstarbench-config (main configuration)"
echo "  ✓ nginx-lua-scripts (API handlers)"
echo "  ✓ nginx-pages (web interface)"
echo "  ✓ nginx-gen-lua (Thrift-generated files)"
echo ""
print_info "To verify:"
echo "  kubectl get configmaps"
echo "  kubectl describe configmap deathstarbench-config"
echo ""
print_warn "Important Note:"
print_info "  The nginx-thrift deployment is already configured to mount these ConfigMaps."
print_info "  However, you may need to update nginx.conf to include gen-lua in lua_package_path."
print_info "  The gen-lua files are mounted at: /usr/local/openresty/nginx/gen-lua"
print_info "  If nginx fails to find Thrift-generated files, add this path to lua_package_path."
echo ""
print_warn "Next steps:"
echo "  1. Verify ConfigMaps were created successfully"
echo "  2. Deploy the application: ./scripts/deploy-gke.sh"
echo "  3. Check nginx-thrift logs if issues occur"
echo "  4. See NEXT_STEPS.md for detailed deployment instructions"
echo ""

