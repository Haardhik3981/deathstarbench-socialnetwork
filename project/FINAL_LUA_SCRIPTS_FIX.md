# Final Fix for nginx-lua-scripts ConfigMap

## The Core Issue

ConfigMap keys **cannot contain `/` characters**, so we can't use paths like `api/home-timeline/read.lua` as keys.

## Working Solution

Since kubectl doesn't recursively include subdirectories and ConfigMap keys can't have slashes, we need to:

1. Create the ConfigMap with valid keys (using underscores instead of slashes)
2. Use an **init container** to recreate the directory structure when the pod starts

But that's complex. For now, let's check if nginx-thrift can work with a simpler setup or if we need to fix the deployment.

## Quick Test

Let's see what nginx actually needs. First, let's check the nginx.conf to see how it references these Lua scripts.

But actually, the SIMPLEST solution right now is to just accept that the ConfigMap is empty and see if nginx-thrift can work without it, or we disable the health checks temporarily.

## Alternative: Just Deploy Without Lua Scripts First

We could:
1. Comment out the lua-scripts volume mount temporarily
2. Get nginx-thrift running first  
3. Then fix the ConfigMap properly later

Would you like to try that approach, or do you want to set up the init container solution?

