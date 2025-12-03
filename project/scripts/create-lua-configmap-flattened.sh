#!/bin/bash

# Create ConfigMap with flattened keys (using underscores instead of slashes)
# Then use an initContainer or script to reorganize files in the pod
# OR update the deployment to handle the flattened structure

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMap (Flattened Keys) ==="
echo ""

# Verify source directory exists
if [ ! -d "${LUA_SCRIPTS_DIR}" ]; then
    echo "ERROR: Lua scripts directory not found at: ${LUA_SCRIPTS_DIR}"
    exit 1
fi

# Delete old ConfigMap
echo "Deleting existing ConfigMap (if any)..."
kubectl delete configmap nginx-lua-scripts 2>/dev/null && echo "✓ Deleted" || echo "  (didn't exist)"

cd "${LUA_SCRIPTS_DIR}"

# Create ConfigMap with keys that use underscores instead of slashes
# Then we'll need to reorganize in the pod
echo ""
echo "Creating ConfigMap with flattened keys (using underscores)..."
echo "Note: Files will need to be reorganized in the pod to restore directory structure"

KUBECTL_CMD="kubectl create configmap nginx-lua-scripts"

FILE_COUNT=0
while IFS= read -r -d '' file; do
    # Remove leading ./
    clean_path=$(echo "$file" | sed 's|^\./||')
    # Replace slashes with underscores for the key
    key_name=$(echo "$clean_path" | sed 's|/|_|g')
    # Add to kubectl command
    KUBECTL_CMD="${KUBECTL_CMD} --from-file=${key_name}=${file}"
    FILE_COUNT=$((FILE_COUNT + 1))
done < <(find . -type f -print0)

echo "Adding $FILE_COUNT files with flattened keys..."

# Execute
if eval "$KUBECTL_CMD" 2>&1; then
    echo "✓ ConfigMap created successfully"
    echo ""
    echo "⚠ NOTE: Keys use underscores instead of slashes"
    echo "   Example: 'wrk2-api_user_register.lua' instead of 'wrk2-api/user/register.lua'"
    echo ""
    echo "To use this, you'll need to either:"
    echo "  1. Update the deployment to reorganize files on startup (initContainer)"
    echo "  2. Or modify the Lua require paths to match the flattened structure"
    echo ""
    echo "For now, let's try a different approach - using a tar-based method..."
    
    # Actually, let's try creating it properly using a workaround
    cd "${PROJECT_ROOT}"
    exit 0
else
    echo "✗ ERROR: Failed to create ConfigMap"
    cd "${PROJECT_ROOT}"
    exit 1
fi

