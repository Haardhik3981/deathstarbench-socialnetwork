#!/bin/bash

# Script to fix readiness probes in all service deployments
# Changes from netstat/ss (not available) to process check (pgrep)

set -e

echo "=== Fixing Readiness Probes in All Deployments ==="
echo ""

# Function to get process name from service name (macOS-compatible)
get_process_name() {
    case "$1" in
        "user-service") echo "UserService" ;;
        "unique-id-service") echo "UniqueIdService" ;;
        "social-graph-service") echo "SocialGraphService" ;;
        "compose-post-service") echo "ComposePostService" ;;
        "home-timeline-service") echo "HomeTimelineService" ;;
        "media-service") echo "MediaService" ;;
        "post-storage-service") echo "PostStorageService" ;;
        "text-service") echo "TextService" ;;
        "url-shorten-service") echo "UrlShortenService" ;;
        "user-mention-service") echo "UserMentionService" ;;
        "user-timeline-service") echo "UserTimelineService" ;;
        "write-home-timeline-service") echo "WriteHomeTimelineService" ;;
        *) echo "" ;;
    esac
}

# Function to update readiness probe
update_readiness_probe() {
    local file=$1
    local process_name=$2
    
    if [ ! -f "$file" ]; then
        echo "  File not found: $file"
        return 1
    fi
    
    # Check if readiness probe exists
    if ! grep -q "readinessProbe:" "$file"; then
        echo "  No readiness probe found, skipping"
        return 0
    fi
    
    # Create backup
    cp "$file" "${file}.backup"
    
    # Replace the readiness probe command
    # Use macOS-compatible sed (no -i with extension, use temp file)
    # Use @ as delimiter to avoid conflicts with | in the pattern
    # Pattern matches: command: ["/bin/sh", "-c", "netstat -an | grep 9090 || ss -an | grep 9090"]
    sed "s@\"netstat -an | grep 9090 || ss -an | grep 9090\"@\"pgrep -f $process_name > /dev/null\"@g" "$file" > "${file}.tmp"
    sed "s@initialDelaySeconds: 5@initialDelaySeconds: 10@g" "${file}.tmp" > "${file}.tmp2"
    mv "${file}.tmp2" "$file"
    rm -f "${file}.tmp"
    
    echo "  ✓ Updated: $file"
}

# Update all service deployments
DEPLOYMENT_DIR="kubernetes/deployments"

# List of services to update
SERVICES=(
    "user-service"
    "unique-id-service"
    "social-graph-service"
    "compose-post-service"
    "home-timeline-service"
    "media-service"
    "post-storage-service"
    "text-service"
    "url-shorten-service"
    "user-mention-service"
    "user-timeline-service"
    "write-home-timeline-service"
)

for service in "${SERVICES[@]}"; do
    process=$(get_process_name "$service")
    file="${DEPLOYMENT_DIR}/${service}-deployment.yaml"
    
    if [ -z "$process" ]; then
        echo "  Unknown service: $service (skipping)"
        continue
    fi
    
    echo "Processing: $service (process: $process)"
    update_readiness_probe "$file" "$process"
    echo ""
done

# Special case for nginx-thrift (HTTP check, not process check)
echo "Processing: nginx-thrift (HTTP check)"
nginx_file="${DEPLOYMENT_DIR}/nginx-thrift-deployment.yaml"
if [ -f "$nginx_file" ]; then
    # nginx-thrift uses HTTP check, which should work
    # Just update initialDelaySeconds if needed
    if grep -q "readinessProbe:" "$nginx_file"; then
        cp "$nginx_file" "${nginx_file}.backup"
        sed "s@initialDelaySeconds: 5@initialDelaySeconds: 10@g" "$nginx_file" > "${nginx_file}.tmp"
        mv "${nginx_file}.tmp" "$nginx_file"
        echo "  ✓ Updated: $nginx_file"
    fi
fi

echo ""
echo "=== Done ==="
echo ""
echo "Backups created with .backup extension"
echo "Now apply the updated deployments:"
echo "  kubectl apply -f kubernetes/deployments/"
echo ""
echo "Then delete pods to restart with new config:"
echo "  ./scripts/quick-restart-all-pods.sh"

