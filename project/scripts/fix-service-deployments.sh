#!/bin/bash

# Script to Fix All Service Deployments
# 
# WHAT THIS DOES:
# Updates all service deployments to mount config files correctly using subPath.
# The services expect files at specific paths, not as a directory mount.

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOYMENTS_DIR="${PROJECT_ROOT}/kubernetes/deployments"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# List of all service deployment files (excluding databases and nginx)
SERVICE_FILES=(
    "compose-post-service-deployment.yaml"
    "social-graph-service-deployment.yaml"
    "user-timeline-service-deployment.yaml"
    "post-storage-service-deployment.yaml"
    "home-timeline-service-deployment.yaml"
    "url-shorten-service-deployment.yaml"
    "media-service-deployment.yaml"
    "text-service-deployment.yaml"
    "unique-id-service-deployment.yaml"
    "user-mention-service-deployment.yaml"
)

print_info "Fixing service deployments to mount config files correctly..."

for service_file in "${SERVICE_FILES[@]}"; do
    filepath="${DEPLOYMENTS_DIR}/${service_file}"
    
    if [ ! -f "$filepath" ]; then
        print_warn "File not found: $filepath (skipping)"
        continue
    fi
    
    # Check if file already has the correct mount format
    if grep -q "subPath: jaeger-config.yml" "$filepath"; then
        print_info "  ✓ ${service_file} already has correct mounts (skipping)"
        continue
    fi
    
    # Create a temporary file with the fix
    # Replace the old volumeMounts section with the new one
    awk '
    /volumeMounts:/ {
        print
        getline
        if ($0 ~ /name: config/) {
            print "        - name: config"
            getline # skip mountPath line
            getline # skip readOnly line
            # Now insert the new mounts
            print "          mountPath: /social-network-microservices/config/jaeger-config.yml"
            print "          subPath: jaeger-config.yml"
            print "          readOnly: true"
            print "        - name: config"
            print "          mountPath: /social-network-microservices/config/service-config.json"
            print "          subPath: service-config.json"
            print "          readOnly: true"
            next
        }
    }
    { print }
    ' "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
    
    print_info "  ✓ Fixed: ${service_file}"
done

print_info "Done! All service deployments have been updated."
print_warn "Next steps:"
echo "  1. Review the changes: git diff kubernetes/deployments/"
echo "  2. Redeploy services: kubectl apply -f kubernetes/deployments/*-service-deployment.yaml"
echo "  3. Check pod logs to verify they start correctly"
