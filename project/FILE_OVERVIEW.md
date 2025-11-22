# File Overview - What Each File Does

This document explains what each file in the project does and why it's needed.

## Root Directory Files

### `README.md`
**What it does**: Main project documentation explaining the overall architecture, components, and structure.
**Why you need it**: Provides a high-level overview of the entire project and how everything fits together.

### `QUICKSTART.md`
**What it does**: Quick reference guide with common commands and concepts.
**Why you need it**: Fast way to get started without reading all the detailed documentation.

### `project_description.txt`
**What it does**: Your original project requirements and design document.
**Why you need it**: Reference for project goals and evaluation criteria.

### `.gitignore`
**What it does**: Tells Git which files to ignore (not track in version control).
**Why you need it**: Prevents committing sensitive data (secrets), temporary files, and test results.

## Docker Directory (`docker/`)

### `docker/nginx/Dockerfile`
**What it does**: Builds a container image for the Nginx reverse proxy.
**Why you need it**: Nginx routes incoming requests to the appropriate microservice. This Dockerfile packages Nginx with your custom configuration.

### `docker/nginx/nginx.conf`
**What it does**: Configuration file for Nginx that defines routing rules.
**Why you need it**: Tells Nginx which URLs should go to which backend service (e.g., `/user/` → user-service).

### `docker/user/Dockerfile`
**What it does**: Builds a container image for the User microservice.
**Why you need it**: Packages the User service (handles user accounts, profiles) into a container. This is a template - you'll need to adapt it to DeathStarBench's actual code.

### `docker/social-graph/Dockerfile`
**What it does**: Builds a container image for the Social Graph service.
**Why you need it**: Packages the service that manages friend connections. Template to adapt.

### `docker/user-timeline/Dockerfile`
**What it does**: Builds a container image for the User Timeline service.
**Why you need it**: Packages the service that manages user activity timelines. Template to adapt.

### `docker/compose/docker-compose.yml`
**What it does**: Defines all services and their relationships for local testing.
**Why you need it**: Allows you to run the entire stack locally with one command (`docker-compose up`) before deploying to Kubernetes.

## Kubernetes Directory (`kubernetes/`)

### Deployments (`kubernetes/deployments/`)

#### `nginx-deployment.yaml`
**What it does**: Tells Kubernetes how to run Nginx pods (how many, what image, resources, health checks).
**Why you need it**: Kubernetes uses this to create and manage Nginx containers. Defines scaling, updates, and resource limits.

#### `user-service-deployment.yaml`
**What it does**: Defines how to run User service pods.
**Why you need it**: Manages the User microservice - how many replicas, what resources, how to check if it's healthy.

#### `social-graph-service-deployment.yaml`
**What it does**: Defines how to run Social Graph service pods.
**Why you need it**: Manages the Social Graph microservice deployment.

#### `user-timeline-service-deployment.yaml`
**What it does**: Defines how to run User Timeline service pods.
**Why you need it**: Manages the User Timeline microservice deployment.

### Services (`kubernetes/services/`)

#### `nginx-service.yaml`
**What it does**: Creates a stable network endpoint for Nginx pods.
**Why you need it**: Provides a consistent way to access Nginx even when pods restart or move. Exposes the service to the internet (LoadBalancer/NodePort).

#### `user-service.yaml`
**What it does**: Creates a stable network endpoint for User service pods.
**Why you need it**: Other services (like Nginx) can connect to "user-service" and Kubernetes routes traffic to healthy pods.

#### `social-graph-service.yaml`
**What it does**: Creates a stable network endpoint for Social Graph service.
**Why you need it**: Provides stable access to the Social Graph service.

#### `user-timeline-service.yaml`
**What it does**: Creates a stable network endpoint for User Timeline service.
**Why you need it**: Provides stable access to the User Timeline service.

### Autoscaling (`kubernetes/autoscaling/`)

#### `user-service-hpa.yaml`
**What it does**: Automatically scales the number of User service pods based on CPU/memory usage.
**Why you need it**: When traffic increases, HPA creates more pods. When traffic decreases, it removes pods. This maintains performance while optimizing costs.

#### `user-service-vpa.yaml`
**What it does**: Automatically adjusts CPU/memory requests and limits for User service pods.
**Why you need it**: Learns from actual usage and optimizes resource allocation. Can reduce costs by not over-provisioning.

### Monitoring (`kubernetes/monitoring/`)

#### `prometheus-configmap.yaml`
**What it does**: Configuration file for Prometheus that defines what metrics to collect and from where.
**Why you need it**: Tells Prometheus which services to monitor and how often to collect metrics.

#### `prometheus-deployment.yaml`
**What it does**: Deploys Prometheus to collect and store metrics.
**Why you need it**: Prometheus collects performance metrics (CPU, memory, request rates) from all your services. Essential for understanding system behavior.

#### `grafana-deployment.yaml`
**What it does**: Deploys Grafana for visualizing metrics in dashboards.
**Why you need it**: Creates beautiful dashboards from Prometheus data. Makes it easy to see system performance, identify bottlenecks, and track trends.

### ConfigMaps (`kubernetes/configmaps/`)

#### `nginx-config.yaml`
**What it does**: Stores the Nginx configuration file as a Kubernetes ConfigMap.
**Why you need it**: Separates configuration from container images. You can update configuration without rebuilding images.

#### `database-secret.yaml`
**What it does**: Stores database connection credentials securely.
**Why you need it**: Keeps sensitive data (passwords) separate from code. Services reference this secret to get database credentials.

## k6 Tests Directory (`k6-tests/`)

### `constant-load.js`
**What it does**: Simulates a steady, constant number of users making requests.
**Why you need it**: Establishes baseline performance metrics. Tests if the system can handle expected production traffic.

### `peak-test.js`
**What it does**: Simulates a sudden traffic spike (e.g., viral post).
**Why you need it**: Tests how the system handles sudden load increases. Validates autoscaling behavior and identifies maximum capacity.

### `stress-test.js`
**What it does**: Gradually increases load to find the breaking point.
**Why you need it**: Identifies maximum sustainable throughput and resource bottlenecks. Shows how performance degrades as load increases.

### `endurance-test.js`
**What it does**: Runs moderate load for hours to find long-term issues.
**Why you need it**: Identifies memory leaks, resource exhaustion, and performance degradation over time. Essential for production readiness.

## Scripts Directory (`scripts/`)

### `deploy-gke.sh`
**What it does**: Automates deployment to Google Kubernetes Engine.
**Why you need it**: Handles all the steps: building images, pushing to registry, creating resources, setting up monitoring. Saves time and reduces errors.

### `deploy-nautilus.sh`
**What it does**: Automates deployment to Nautilus cluster.
**Why you need it**: Similar to GKE script but adapted for Nautilus (NodePort instead of LoadBalancer, different setup requirements).

### `setup-monitoring.sh`
**What it does**: Sets up Prometheus and Grafana independently.
**Why you need it**: Allows you to add monitoring to an existing deployment or set it up separately.

### `run-k6-tests.sh`
**What it does**: Convenient wrapper for running k6 load tests.
**Why you need it**: Sets the correct base URL, saves results, and provides a simple interface for running different test types.

## Documentation Directory (`docs/`)

### `deployment-guide.md`
**What it does**: Step-by-step instructions for deploying the entire system.
**Why you need it**: Detailed guide covering prerequisites, deployment steps, troubleshooting, and next steps.

## Key Takeaways

1. **Dockerfiles** = Package applications into containers
2. **Kubernetes Deployments** = Define how to run containers
3. **Kubernetes Services** = Provide stable network access
4. **HPA/VPA** = Automatically scale and optimize resources
5. **Prometheus** = Collect metrics
6. **Grafana** = Visualize metrics
7. **k6 Tests** = Validate performance under load
8. **Scripts** = Automate common tasks

Each file has a specific purpose, and together they create a complete, production-ready microservice deployment system!

