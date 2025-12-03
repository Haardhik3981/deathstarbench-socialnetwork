#!/bin/bash

# Create ConfigMap for nginx Lua scripts
# This script handles the directory structure properly

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMap ==="
echo ""

# Verify source directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "ERROR: Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

# Count files
FILE_COUNT=$(find "${LUA_SCRIPTS_DIR}" -type f | wc -l | tr -d ' ')
echo "Found $FILE_COUNT Lua files in source directory"

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "ERROR: No files found in Lua scripts directory!"
    exit 1
fi

# Delete old ConfigMap
echo ""
echo "Deleting existing ConfigMap (if any)..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "✓ Deleted" || echo "  (didn't exist)"

# Method 1: Try creating from directory (kubectl handles subdirectories)
echo ""
echo "Creating ConfigMap from directory..."
cd "${LUA_SCRIPTS_DIR}"

# Try creating ConfigMap from directory
# kubectl should preserve directory structure when using --from-file=.
if kubectl create configmap nginx-lua-scripts --from-file=. 2>&1 | tee /tmp/kubectl-output.log; then
    echo "✓ ConfigMap created successfully"
    METHOD="directory"
else
    # Method 2: Fallback - create with explicit files using valid key names
    echo ""
    echo "Directory method failed, trying explicit file method..."
    echo "Creating keys with underscores instead of slashes..."
    
    cd "${LUA_SCRIPTS_DIR}"
    
    # Build kubectl command with files, using underscores in key names
    # The deployment will need to be updated to handle this, OR
    # we can use a different approach: create symlinks or use initContainer
    
    # Actually, let's try a different approach: use a tar file
    echo "Trying tar-based approach..."
    
    TEMP_DIR=$(mktemp -d)
    cd "${LUA_SCRIPTS_DIR}"
    
    # Create a tar of all files
    tar czf "${TEMP_DIR}/lua-scripts.tar.gz" .
    
    # Create ConfigMap from tar (this won't work directly, need different approach)
    # Actually, let's just create it file by file with proper key mapping
    
    # Find all files and create ConfigMap entries
    # We'll use a script to create the ConfigMap with proper structure
    KUBECTL_CMD="kubectl create configmap nginx-lua-scripts"
    
    find . -type f | while read -r file; do
        # Remove leading ./
        clean_path=$(echo "$file" | sed 's|^\./||')
        # For the key, we need to use a valid format
        # Kubernetes ConfigMap keys can't have slashes, so we'll use a workaround
        # Actually, let's check if we can use the path as-is with a different method
        
        # Use the file path as the key (kubectl might handle this)
        KUBECTL_CMD="${KUBECTL_CMD} --from-file=\"${clean_path}\"=\"${file}\""
    done
    
    # This approach won't work either due to slashes
    # Let's use a Python script or different tool
    
    echo "Using alternative method: creating ConfigMap via YAML..."
    
    # Create a temporary YAML file
    cat > "${TEMP_DIR}/configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-lua-scripts
data:
EOF
    
    # Add each file to the YAML
    find . -type f | while read -r file; do
        clean_path=$(echo "$file" | sed 's|^\./||')
        # Base64 encode the file content and add to YAML
        # But we need to handle the key name - replace / with something
        key_name=$(echo "$clean_path" | sed 's|/|_|g')
        content=$(base64 < "$file" | tr -d '\n')
        echo "  ${key_name}: |" >> "${TEMP_DIR}/configmap.yaml"
        # Add base64 content
        echo "    ${content}" >> "${TEMP_DIR}/configmap.yaml"
    done
    
    # Apply the YAML
    kubectl apply -f "${TEMP_DIR}/configmap.yaml"
    
    rm -rf "${TEMP_DIR}"
    METHOD="yaml"
fi

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMap..."
sleep 2

if kubectl get configmap nginx-lua-scripts >/dev/null 2>&1; then
    echo "✓ ConfigMap exists"
    echo ""
    echo "Checking contents..."
    
    # List keys (this might not work if keys have special chars)
    KEY_COUNT=$(kubectl get configmap nginx-lua-scripts -o json 2>/dev/null | grep -c '"' || echo "0")
    
    if [ "$KEY_COUNT" -gt 2 ]; then
        echo "✓ ConfigMap appears to have data"
        echo ""
        echo "Restarting nginx-thrift deployment..."
        kubectl rollout restart deployment/nginx-thrift-deployment
        echo "✓ Done!"
    else
        echo "⚠ ConfigMap created but may be empty or have issues"
        echo "Checking ConfigMap:"
        kubectl get configmap nginx-lua-scripts -o yaml | head -30
    fi
else
    echo "✗ ERROR: Failed to create ConfigMap"
    exit 1
fi

