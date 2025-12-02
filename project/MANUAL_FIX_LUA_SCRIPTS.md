# Manual Fix for nginx-lua-scripts ConfigMap

## The Problem

kubectl's `--from-file` doesn't seem to be working with subdirectories. Let's try a different approach.

## Try This Script

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project
./scripts/fix-lua-scripts-explicit.sh
```

This script explicitly adds each file individually to the ConfigMap.

## Alternative: Manual Step-by-Step

If the script doesn't work, try this step-by-step:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/socialNetwork/nginx-web-server/lua-scripts

# Delete empty ConfigMap
kubectl delete configmap nginx-lua-scripts

# Create ConfigMap by adding each subdirectory's files explicitly
# First, let's see what files we have:
find . -type f -name "*.lua"

# Then create ConfigMap file by file
# This preserves the directory structure in the keys
kubectl create configmap nginx-lua-scripts \
  --from-file=api/home-timeline/read.lua=api/home-timeline/read.lua \
  --from-file=api/post/compose.lua=api/post/compose.lua \
  --from-file=api/user/follow.lua=api/user/follow.lua \
  --from-file=api/user/get_followee.lua=api/user/get_followee.lua \
  --from-file=api/user/get_follower.lua=api/user/get_follower.lua \
  --from-file=api/user/login.lua=api/user/login.lua \
  --from-file=api/user/register.lua=api/user/register.lua \
  --from-file=api/user/unfollow.lua=api/user/unfollow.lua \
  --from-file=api/user-timeline/read.lua=api/user-timeline/read.lua \
  --from-file=wrk2-api/home-timeline/read.lua=wrk2-api/home-timeline/read.lua \
  --from-file=wrk2-api/post/compose.lua=wrk2-api/post/compose.lua \
  --from-file=wrk2-api/user/follow.lua=wrk2-api/user/follow.lua \
  --from-file=wrk2-api/user/register.lua=wrk2-api/user/register.lua \
  --from-file=wrk2-api/user/unfollow.lua=wrk2-api/user/unfollow.lua \
  --from-file=wrk2-api/user-timeline/read.lua=wrk2-api/user-timeline/read.lua

# Verify
kubectl get configmap nginx-lua-scripts
```

## Or Use a Loop

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/socialNetwork/nginx-web-server/lua-scripts

kubectl delete configmap nginx-lua-scripts 2>/dev/null

# Build command dynamically
CMD="kubectl create configmap nginx-lua-scripts"
for file in $(find . -type f -name "*.lua"); do
    key=$(echo "$file" | sed 's|^\./||')
    CMD="$CMD --from-file=${key}=${file}"
done

# Execute the command
eval $CMD

# Verify
kubectl get configmap nginx-lua-scripts
```

Try the script first - it should work!

