#!/bin/bash

# Create ConfigMap by explicitly adding each file
# This ensures all files in subdirectories are included

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LUA_SCRIPTS_DIR="${PROJECT_ROOT}/../socialNetwork/nginx-web-server/lua-scripts"

echo "=== Creating nginx-lua-scripts ConfigMap (Explicit Method) ==="
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

# Build kubectl command with all files
echo ""
echo "Building ConfigMap with all files (this may take a moment)..."
cd "${LUA_SCRIPTS_DIR}"

# Find all files and add them to the ConfigMap
# Use --from-file with key=file format where key is the relative path
KUBECTL_CMD="kubectl create configmap nginx-lua-scripts"

# Process each file
FILE_ADDED=0
while IFS= read -r -d '' file; do
    # Remove leading ./
    clean_path=$(echo "$file" | sed 's|^\./||')
    # Add to kubectl command
    # Format: --from-file=key=filepath
    # The key will be the relative path, which kubectl should handle
    KUBECTL_CMD="${KUBECTL_CMD} --from-file=\"${clean_path}\"=\"${file}\""
    FILE_ADDED=$((FILE_ADDED + 1))
    if [ $((FILE_ADDED % 5)) -eq 0 ]; then
        echo "  Added $FILE_ADDED files..."
    fi
done < <(find . -type f -print0)

echo "  Total: $FILE_ADDED files"
echo ""
echo "Creating ConfigMap..."

# Execute the command
# Note: We need to eval because the command is built dynamically
if eval "$KUBECTL_CMD" 2>&1; then
    echo "✓ ConfigMap created successfully"
else
    echo ""
    echo "✗ ERROR: Failed to create ConfigMap"
    echo "This might be due to key name restrictions."
    echo ""
    echo "Trying alternative: Create ConfigMap using YAML generation..."
    
    # Alternative: Create via YAML
    TEMP_YAML=$(mktemp)
    cat > "$TEMP_YAML" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-lua-scripts
data:
EOF
    
    # Add each file to YAML
    while IFS= read -r -d '' file; do
        clean_path=$(echo "$file" | sed 's|^\./||')
        # For YAML, we need to base64 encode or use literal block
        # Actually, let's use literal block scalar (|) for each file
        echo "  ${clean_path}: |" >> "$TEMP_YAML"
        # Indent file content
        sed 's/^/    /' "$file" >> "$TEMP_YAML"
    done < <(find . -type f -print0)
    
    # Apply YAML
    if kubectl apply -f "$TEMP_YAML" 2>&1; then
        echo "✓ ConfigMap created via YAML"
        rm -f "$TEMP_YAML"
    else
        echo "✗ ERROR: YAML method also failed"
        rm -f "$TEMP_YAML"
        cd "${PROJECT_ROOT}"
        exit 1
    fi
fi

cd "${PROJECT_ROOT}"

# Verify
echo ""
echo "Verifying ConfigMap..."
sleep 2

if kubectl get configmap nginx-lua-scripts >/dev/null 2>&1; then
    # Try to get a key to verify data exists
    if kubectl get configmap nginx-lua-scripts -o jsonpath='{.data}' >/dev/null 2>&1; then
        # Count keys (rough estimate)
        KEY_COUNT=$(kubectl get configmap nginx-lua-scripts -o json | grep -c '":' || echo "0")
        
        if [ "$KEY_COUNT" -gt 10 ]; then
            echo "✓ SUCCESS! ConfigMap appears to have data"
            echo ""
            echo "Restarting nginx-thrift deployment..."
            kubectl rollout restart deployment/nginx-thrift-deployment
            echo "✓ Done!"
        else
            echo "⚠ ConfigMap exists but verification unclear"
            echo "Checking with describe:"
            kubectl describe configmap nginx-lua-scripts | head -20
        fi
    else
        echo "⚠ Could not verify data section"
        kubectl get configmap nginx-lua-scripts -o yaml | head -30
    fi
else
    echo "✗ ERROR: ConfigMap was not created"
    exit 1
fi

