# Directory Structure Explained

## Overview

You have two main directories that serve different purposes but need to work together:

1. **`socialNetwork/`** - The official DeathStarBench source code (for local development)
2. **`project/`** - Your Kubernetes deployment project (for GKE/Nautilus deployment)

## Directory 1: `socialNetwork/` (Official DeathStarBench)

### What It Is:
This is the **official DeathStarBench repository** containing the actual source code, Dockerfiles, and configuration files for the social network benchmark.

### What It Contains:
```
socialNetwork/
├── docker-compose.yml          # Runs everything locally using pre-built images
├── Dockerfile                  # Builds the unified microservices image
├── src/                        # C++ source code for all microservices
├── config/                     # Configuration files (service-config.json, etc.)
├── nginx-web-server/           # Nginx-thrift gateway files (Lua scripts, pages, config)
├── gen-lua/                    # Generated Lua code for Thrift
├── scripts/                    # Initialization scripts
└── ...                         # Other DeathStarBench files
```

### Purpose:
- **Local Development**: Run `docker-compose up` here to test the entire stack locally
- **Source of Truth**: Contains the actual application code and configuration
- **Pre-built Images**: Uses `deathstarbench/social-network-microservices:latest` from Docker Hub

### How to Use It:
```bash
cd socialNetwork/
docker-compose up  # Runs all services locally
```

This works because it uses **pre-built images** from Docker Hub. You don't need to build anything.

---

## Directory 2: `project/` (Your Kubernetes Deployment)

### What It Is:
This is **your custom Kubernetes deployment project** that takes the DeathStarBench application and deploys it to Kubernetes (GKE or Nautilus).

### What It Contains:
```
project/
├── kubernetes/                 # All Kubernetes manifests
│   ├── deployments/            # Pod definitions
│   ├── services/              # Service definitions
│   ├── configmaps/            # Configuration
│   └── monitoring/            # Prometheus/Grafana
├── scripts/                   # Deployment automation
│   └── deploy-gke.sh          # Script to deploy to GKE
├── k6-tests/                  # Load testing scripts
└── docker/                     # ⚠️ These are TEMPLATES, not actual Dockerfiles
```

### Purpose:
- **Kubernetes Deployment**: Deploy DeathStarBench to GKE or Nautilus
- **Production Setup**: Includes monitoring, autoscaling, etc.
- **Customization**: Your project-specific configurations

### Important Note:
The `project/docker/` directory contains **template Dockerfiles** that we created for learning purposes. They are **NOT** the actual DeathStarBench Dockerfiles. The real Dockerfile is in `socialNetwork/Dockerfile`.

---

## How They Work Together

### The Problem:
Your `deploy-gke.sh` script currently tries to build images from `project/docker/`, but:
1. Those are just templates, not real Dockerfiles
2. The actual source code and Dockerfile are in `socialNetwork/`
3. DeathStarBench uses a **single unified image** with different entrypoints, not separate images per service

### The Solution:
You have **two options**:

---

## Option 1: Use Pre-built Images (Easiest - Recommended)

DeathStarBench already provides pre-built images on Docker Hub. You can use these directly without building anything.

### Update `deploy-gke.sh`:
Instead of building images, just use the pre-built ones:

```bash
# In deploy-gke.sh, replace build_and_push_images() with:
build_and_push_images() {
    print_info "Using pre-built DeathStarBench images from Docker Hub..."
    
    # No need to build - DeathStarBench images are already on Docker Hub
    # Just update your Kubernetes manifests to use:
    # image: deathstarbench/social-network-microservices:latest
    
    print_info "Images will be pulled from Docker Hub during deployment"
}
```

Then update your Kubernetes deployment YAMLs to use:
```yaml
image: deathstarbench/social-network-microservices:latest
```

**Pros:**
- ✅ No building required
- ✅ Fastest option
- ✅ Uses official tested images

**Cons:**
- ❌ Can't customize the application code
- ❌ Depends on external Docker Hub

---

## Option 2: Build from Source (For Customization)

If you need to customize the code or use your own registry, build from the `socialNetwork/` directory.

### Update `deploy-gke.sh`:
```bash
build_and_push_images() {
    print_info "Building DeathStarBench image from source..."
    
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # Point to the actual DeathStarBench source
    DSB_ROOT="${PROJECT_ROOT}/../socialNetwork"
    
    if [ ! -f "${DSB_ROOT}/Dockerfile" ]; then
        print_error "DeathStarBench source not found at ${DSB_ROOT}"
        exit 1
    fi
    
    # Build the unified microservices image
    print_info "Building unified microservices image..."
    docker build -t "${REGISTRY}/social-network-microservices:${IMAGE_TAG}" "${DSB_ROOT}"
    docker push "${REGISTRY}/social-network-microservices:${IMAGE_TAG}"
    
    # Build nginx-thrift (if you need custom version)
    # The nginx-thrift image is more complex - you may want to use the pre-built one
    # docker build -t "${REGISTRY}/nginx-thrift:${IMAGE_TAG}" "${DSB_ROOT}/docker/openresty-thrift"
    
    print_info "Images built and pushed!"
}
```

Then update all your Kubernetes deployments to use:
```yaml
image: us-central1-docker.pkg.dev/YOUR_PROJECT/social-network-images/social-network-microservices:latest
```

**Pros:**
- ✅ Can customize application code
- ✅ Use your own container registry
- ✅ Full control

**Cons:**
- ❌ Requires building (takes time)
- ❌ More complex setup

---

## Recommended Approach

### For Local Development:
```bash
cd socialNetwork/
docker-compose up
```
Use the official DeathStarBench docker-compose - it's designed for this.

### For Kubernetes Deployment:
1. **Use pre-built images** (Option 1) for simplicity
2. **Update your Kubernetes YAMLs** to reference `deathstarbench/social-network-microservices:latest`
3. **Copy configuration files** from `socialNetwork/config/` to Kubernetes ConfigMaps
4. **Run your deployment scripts** from `project/` directory

---

## File Flow Diagram

```
┌─────────────────────────────────────┐
│  socialNetwork/                     │
│  (Official DeathStarBench)          │
│                                     │
│  ├── docker-compose.yml            │  Uses pre-built images
│  ├── Dockerfile                     │  Builds unified image
│  ├── config/                        │  Configuration files
│  └── nginx-web-server/              │  Gateway files
│                                     │
│  Purpose: Local development         │
└─────────────────────────────────────┘
              │
              │ Copy config files
              │ Reference source code
              ▼
┌─────────────────────────────────────┐
│  project/                           │
│  (Your Kubernetes Project)          │
│                                     │
│  ├── kubernetes/                    │  K8s manifests
│  ├── scripts/                        │  deploy-gke.sh
│  └── k6-tests/                      │  Load tests
│                                     │
│  Purpose: K8s deployment             │
└─────────────────────────────────────┘
```

---

## Key Takeaways

1. **`socialNetwork/`** = Source code + Local development
2. **`project/`** = Kubernetes deployment + Production setup
3. **Don't try to run docker-compose from `project/`** - it's not set up for that
4. **Use `socialNetwork/docker-compose.yml`** for local testing
5. **Use `project/scripts/deploy-gke.sh`** for Kubernetes deployment
6. **Either use pre-built images OR build from `socialNetwork/Dockerfile`**

---

## Next Steps

1. **For local testing**: Use `socialNetwork/docker-compose.yml`
2. **For GKE deployment**: 
   - Update `deploy-gke.sh` to use pre-built images (Option 1), OR
   - Update it to build from `socialNetwork/Dockerfile` (Option 2)
3. **Copy config files**: From `socialNetwork/config/` to Kubernetes ConfigMaps
4. **Test deployment**: Run `./scripts/deploy-gke.sh` from `project/` directory

