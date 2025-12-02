# nginx-thrift ConfigMap Solution

## The Problem

- ConfigMap keys cannot contain `/` characters  
- kubectl `--from-file` doesn't recursively process subdirectories
- We need directory structure preserved (`api/`, `wrk2-api/`)

## Why This Is Hard

The files are in:
```
lua-scripts/
  api/
    home-timeline/read.lua
    post/compose.lua
    ...
  wrk2-api/
    ...
```

But ConfigMap keys like `api/home-timeline/read.lua` are invalid.

## Solution Options

### Option 1: Init Container (Recommended)
- Create flattened ConfigMap with valid keys (`api_home_timeline_read.lua`)
- Use init container to copy files to proper directory structure in emptyDir
- nginx reads from emptyDir with correct structure

### Option 2: Multiple ConfigMaps
- Create separate ConfigMap per subdirectory
- Mount each ConfigMap at appropriate path
- More complex deployment changes needed

### Option 3: Check if nginx can work without directory structure
- Some nginx configs can reference files differently
- May require nginx.conf changes

## For Now - Quick Decision

Since this is blocking nginx-thrift, we have two choices:

1. **Temporarily disable lua-scripts** - Get nginx running first, fix ConfigMap later
2. **Implement init container solution** - Proper fix but takes more time

Which would you prefer? The init container solution is the "proper" fix, but disabling temporarily lets us test other parts of the system first.

