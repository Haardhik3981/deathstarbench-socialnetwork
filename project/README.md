# DeathStarBench Social Network - Kubernetes Deployment Project

## Overview

This project implements a complete microservice deployment pipeline for the DeathStarBench Social Network benchmark. The system includes containerization, Kubernetes orchestration, autoscaling (HPA/VPA), monitoring (Prometheus/Grafana), and comprehensive load testing.

## Project Structure

```
project/
├── README.md                    # This file - project overview
├── DEPLOYMENT_GUIDE.md          # Step-by-step deployment instructions
├── CI_CD_DOCUMENTATION.md       # GitHub Actions CI/CD pipeline documentation
├── TESTERS_MANUAL.md            # Comprehensive testing guide
├── VPA_VS_HPA_COMPARISON.md     # Comparison of autoscaling approaches
├── project_description.txt      # Original project requirements
│
├── docker/                      # Dockerfiles for containerization
│   ├── nginx/                   # Nginx reverse proxy
│   ├── user/                    # User service
│   ├── social-graph/            # Social graph service
│   ├── user-timeline/           # User timeline service
│   └── compose/                 # Docker Compose for local testing
│
├── kubernetes/                  # Kubernetes manifests
│   ├── deployments/             # Deployment configurations
│   ├── services/                # Service definitions (ClusterIP, NodePort)
│   ├── autoscaling/             # HPA and VPA configurations
│   ├── monitoring/              # Prometheus and Grafana setup
│   └── configmaps/              # Configuration files as ConfigMaps
│
├── k6-tests/                    # Load testing scripts
│   └── README.md                # Test documentation
│
├── scripts/                     # Helper scripts
│   └── README.md                # Script documentation
│
├── k6-results/                  # Test results (generated)
└── docs/                        # Additional documentation
```

## Key Components

### Application
- **DeathStarBench Social Network**: Microservice benchmark simulating a social network
- **Services**: User, Social Graph, Timeline, Post Storage, Media, etc.

### Containerization
- **Docker**: Packages each microservice with dependencies
- **Docker Compose**: Local development and testing

### Orchestration
- **Kubernetes**: Manages container lifecycle, networking, and scaling
- **Deployments**: Pod management and rolling updates
- **Services**: Service discovery and load balancing

### Autoscaling
- **HPA (Horizontal Pod Autoscaler)**: Scales pod replicas based on CPU/memory/latency
- **VPA (Vertical Pod Autoscaler)**: Adjusts CPU/memory requests/limits per pod
- See `kubernetes/autoscaling/README.md` for details

### Monitoring
- **Prometheus**: Time-series metrics collection
- **Grafana**: Metrics visualization and dashboards
- See `kubernetes/monitoring/METRICS_TRACKING_GUIDE.md` for queries

### Load Testing
- **k6**: Performance testing framework
- **Test Types**: Constant load, peak, stress, endurance, CPU-intensive
- See `k6-tests/README.md` for test details

## Quick Start

### Prerequisites
- Docker Desktop
- kubectl CLI
- gcloud CLI (for GKE)
- k6 installed (`brew install k6`)

### Deployment
1. **Set up cluster access**: `kubectl config use-context <your-cluster>`
2. **Deploy services**: `./deploy-everything.sh` or see `DEPLOYMENT_GUIDE.md`
3. **Set up monitoring**: Deploy Prometheus/Grafana from `kubernetes/monitoring/`
4. **Run tests**: `./scripts/run-test-with-metrics.sh <test-name>`

### Testing
1. **Reset databases**: `./scripts/reset-all-databases.sh`
2. **Verify system**: `./scripts/verify-system-ready.sh`
3. **Port-forward**: `kubectl port-forward svc/nginx-thrift-service 8080:8080`
4. **Run test**: `./scripts/run-test-with-metrics.sh sweet-test`

## Documentation

- **DEPLOYMENT_GUIDE.md**: Complete deployment instructions
- **TESTERS_MANUAL.md**: Testing workflow and best practices
- **CI_CD_DOCUMENTATION.md**: GitHub Actions pipeline details
- **VPA_VS_HPA_COMPARISON.md**: Autoscaling strategy comparison
- **kubernetes/autoscaling/README.md**: Autoscaling configuration guide
- **kubernetes/monitoring/METRICS_TRACKING_GUIDE.md**: Prometheus queries
- **k6-tests/README.md**: Load test documentation
- **scripts/README.md**: Script reference

## CI/CD Pipeline

Automated validation and deployment via GitHub Actions:
- Kubernetes manifest validation
- Shell script linting
- Security scanning
- k6 test validation
- Optional automated deployment

See `CI_CD_DOCUMENTATION.md` for details.

## Next Steps

1. Read `DEPLOYMENT_GUIDE.md` for deployment instructions
2. Review `TESTERS_MANUAL.md` for testing workflow
3. Check `kubernetes/autoscaling/README.md` for autoscaling setup
4. Explore `k6-tests/README.md` for available load tests
