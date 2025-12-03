#!/bin/bash

# Create ConfigMap from directory - preserves subdirectory structure
# When mounted, Kubernetes creates the directory structure automatically
# Note: kubectl --from-file=. creates keys with file paths including slashes,
# which Kubernetes handles specially when mounting as a directory

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

# Create ConfigMap from directory
# Using --from-file with directory path creates keys with relative paths, preserving structure
# When mounted, Kubernetes will create the directory structure
echo ""
echo "Creating ConfigMap from directory..."
echo "Note: This preserves the directory structure (api/, wrk2-api/, etc.)"

# Create ConfigMap using the directory path (not changing into it)
# This ensures kubectl can properly read all files
if kubectl create configmap nginx-lua-scripts --from-file="${LUA_SCRIPTS_DIR}" 2>&1; then
    echo "✓ ConfigMap created successfully"
else
    echo ""
    echo "✗ ERROR: Failed to create ConfigMap with directory path"
    echo "Trying alternative: creating from within directory..."
    
    # Alternative: Change into directory and use .
    cd "${LUA_SCRIPTS_DIR}"
    if kubectl create configmap nginx-lua-scripts --from-file=. 2>&1; then
        echo "✓ ConfigMap created successfully (alternative method)"
        cd "${PROJECT_ROOT}"
    else
        echo ""
        echo "✗ ERROR: Both methods failed"
        cd "${PROJECT_ROOT}"
        exit 1
    fi
fi

# Verify
echo ""
echo "Verifying ConfigMap..."
sleep 2

# Check if ConfigMap exists and has data
if kubectl get configmap nginx-lua-scripts >/dev/null 2>&1; then
    # Get the full YAML to check for data
    CM_YAML=$(kubectl get configmap nginx-lua-scripts -o yaml 2>/dev/null)
    
    # Check if data section exists and has content
    if echo "$CM_YAML" | grep -q "^data:"; then
        # Count how many keys are in the data section (look for lines that are keys, not values)
        # Keys are lines that start with spaces, have a colon, and are followed by | or a value
        KEY_COUNT=$(echo "$CM_YAML" | awk '/^data:/{flag=1; next} /^[^ ]/{flag=0} flag && /^  [^ ]+:/ {count++} END {print count+0}' || echo "0")
        
        # Alternative: count lines that look like keys in data section
        if [ "$KEY_COUNT" = "0" ]; then
            # Try a different method - count lines between "data:" and next top-level key
            KEY_COUNT=$(echo "$CM_YAML" | sed -n '/^data:/,/^[a-z]/p' | grep -c '^  [^ ]' || echo "0")
        fi
        
        if [ "$KEY_COUNT" -gt 0 ]; then
            echo "✓ SUCCESS! ConfigMap created with $KEY_COUNT files"
            echo ""
            echo "Sample files in ConfigMap:"
            echo "$CM_YAML" | sed -n '/^data:/,/^[a-z]/p' | grep '^  [^ ]' | head -5 | sed 's/:.*$//' | sed 's/^  //' || echo "  (showing structure...)"
            echo ""
            echo "Restarting nginx-thrift deployment..."
            kubectl rollout restart deployment/nginx-thrift-deployment
            echo "✓ Deployment restarted!"
            echo ""
            echo "Waiting for rollout to complete..."
            kubectl rollout status deployment/nginx-thrift-deployment --timeout=60s 2>&1 || echo "  (rollout may still be in progress - check with: kubectl get pods -l app=nginx-thrift)"
            echo ""
            echo "✓ Done! The nginx-thrift pod should now have access to all Lua scripts."
            echo ""
            echo "To verify the files are mounted, check:"
            echo "  kubectl exec -it \$(kubectl get pod -l app=nginx-thrift -o jsonpath='{.items[0].metadata.name}') -- ls -la /usr/local/openresty/nginx/lua-scripts/wrk2-api/user/"
        else
            echo "⚠ WARNING: ConfigMap created but data section appears empty"
            echo "Full ConfigMap YAML:"
            echo "$CM_YAML" | head -40
        fi
    else
        echo "✗ ERROR: ConfigMap created but 'data:' section is missing"
        echo "Full ConfigMap YAML:"
        echo "$CM_YAML"
        echo ""
        echo "This might indicate kubectl didn't properly read the directory."
        echo "Try checking if files are readable:"
        echo "  ls -la ${LUA_SCRIPTS_DIR}/wrk2-api/user/"
    fi
else
    echo "✗ ERROR: Failed to create ConfigMap"
    exit 1
fi

