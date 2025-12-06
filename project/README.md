# DeathStarBench Social Network - Kubernetes Deployment Project

## Overview

This project implements a complete microservice deployment pipeline for the DeathStarBench Social Network benchmark. The system includes containerization, Kubernetes orchestration, autoscaling, monitoring, and comprehensive load testing.

## Project Structure

```
project/
├── README.md                    # This file - project overview and documentation
├── docker/                      # Dockerfiles for each microservice
│   ├── nginx/                   # Nginx reverse proxy Dockerfile
│   ├── social-graph/            # Social graph service Dockerfile
│   ├── user-timeline/           # User timeline service Dockerfile
│   ├── user/                    # User service Dockerfile
│   └── compose/                 # Docker Compose for local testing
├── kubernetes/                  # Kubernetes manifests
│   ├── deployments/             # Deployment manifests for each service
│   ├── services/                # Service manifests (ClusterIP, NodePort, etc.)
│   ├── autoscaling/             # HPA and VPA configurations
│   ├── monitoring/              # Prometheus and Grafana setup
│   └── configmaps/              # Configuration files as ConfigMaps
├── k6-tests/                    # k6 load testing scripts
│   ├── constant-load.js         # Constant load test
│   ├── peak-test.js             # Peak/spike test
│   ├── stress-test.js           # Stress test (gradual ramp-up)
│   └── endurance-test.js        # Endurance test (long duration)
├── scripts/                     # Helper scripts for deployment
│   ├── deploy-gke.sh            # Deploy to Google Kubernetes Engine
│   ├── deploy-nautilus.sh       # Deploy to Nautilus cluster
│   └── setup-monitoring.sh      # Set up Prometheus and Grafana
└── docs/                        # Additional documentation
    └── deployment-guide.md      # Step-by-step deployment instructions
```

## Components

### 1. Application: DeathStarBench Social Network
- **What it is**: A microservice benchmark suite that simulates a social network
- **Why we use it**: Industry-standard benchmark for evaluating microservice performance
- **Key services**: User service, Social Graph service, User Timeline service, etc.

### 2. Containerization (Docker)
- **What it does**: Packages each microservice with its dependencies into isolated containers
- **Why it matters**: Ensures consistent behavior across different environments (local, GKE, Nautilus)

### 3. Orchestration (Kubernetes)
- **What it does**: Manages container lifecycle, networking, scaling, and resource allocation
- **Why it matters**: Automates deployment and scaling, handles failures automatically

### 4. Autoscaling
- **HPA (Horizontal Pod Autoscaler)**: Automatically increases/decreases the number of pod replicas
- **VPA (Vertical Pod Autoscaler)**: Automatically adjusts CPU/memory limits per pod
- **Why it matters**: Optimizes resource usage and maintains performance under varying load

### 5. Monitoring (Prometheus & Grafana)
- **Prometheus**: Collects time-series metrics from all services
- **Grafana**: Visualizes metrics in dashboards
- **Why it matters**: Provides visibility into system performance and helps identify bottlenecks

### 6. Load Testing (k6)
- **What it does**: Simulates user traffic to test system performance
- **Test types**: Constant load, peak testing, stress testing, endurance testing
- **Why it matters**: Validates that the system can handle expected and peak loads

## Quick Start

### Prerequisites
- Docker Desktop installed
- kubectl CLI installed
- gcloud CLI installed (for GKE)
- k6 installed
- Access to GKE cluster or Nautilus cluster

### Local Development
1. Clone DeathStarBench repository
2. Build Docker images: `docker-compose build`
3. Run locally: `docker-compose up`

### Kubernetes Deployment
1. Set up cluster access: `kubectl config use-context <your-cluster>`
2. Deploy services: `./scripts/deploy-gke.sh` or `./scripts/deploy-nautilus.sh`
3. Set up monitoring: `./scripts/setup-monitoring.sh`
4. Run load tests: `k6 run k6-tests/constant-load.js`

## Testing Strategy

1. **Constant Load Test**: Baseline performance measurement
2. **Peak Test**: Sudden traffic spike to test autoscaling
3. **Stress Test**: Gradual ramp-up to find breaking points
4. **Endurance Test**: Long-running test to check for resource leaks

## Metrics to Monitor

- **Latency**: p95, p99 response times
- **Throughput**: Requests per second (RPS)
- **Resource Usage**: CPU and memory utilization
- **Scaling Behavior**: Pod count over time
- **Error Rates**: Failed requests percentage

## CI/CD Pipeline

This project includes a comprehensive CI/CD pipeline using GitHub Actions:

- **Automatic Validation**: Kubernetes manifests are validated on every push
- **Code Quality**: Shell scripts are linted for best practices
- **Security Scanning**: Automated security vulnerability scanning
- **k6 Test Validation**: Load test scripts are validated for syntax
- **Optional Deployment**: Can deploy to Kubernetes clusters automatically

**Documentation**: See [CI_CD_DOCUMENTATION.md](CI_CD_DOCUMENTATION.md) for complete details.

**Workflow File**: `.github/workflows/project-ci-cd.yaml`

## Next Steps

See individual file comments for detailed explanations of each component.

