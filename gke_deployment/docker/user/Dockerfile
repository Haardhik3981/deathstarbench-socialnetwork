# Dockerfile for User Service
#
# WHAT THIS DOES:
# This Dockerfile packages the User microservice into a container. The User service
# handles user-related operations like creating user accounts, retrieving user profiles,
# and updating user information.
#
# NOTE: This is a template Dockerfile. DeathStarBench's actual User service may be
# written in different languages (Go, Java, Python, etc.). You'll need to adapt this
# based on the actual implementation.
#
# KEY CONCEPTS:
# - Multi-stage build: Uses a builder stage to compile code, then copies only the
#   compiled binary to a smaller runtime image (reduces final image size)
# - Environment variables: Allow configuration without rebuilding the image
# - Health checks: Kubernetes uses these to determine if the container is healthy

# Stage 1: Build stage
# This stage compiles the application code
FROM golang:1.21-alpine AS builder

# Set working directory inside the container
WORKDIR /app

# Install build dependencies
# git: Needed to fetch Go dependencies
# ca-certificates: Needed for HTTPS connections
RUN apk add --no-cache git ca-certificates

# Copy dependency files first (for better Docker layer caching)
# If these files don't change, Docker can reuse cached layers
COPY go.mod go.sum ./

# Download dependencies
# This step is cached unless go.mod or go.sum changes
RUN go mod download

# Copy the rest of the source code
COPY . .

# Build the application
# CGO_ENABLED=0: Disables CGO (creates a static binary)
# GOOS=linux: Builds for Linux (required for containers)
# -o user-service: Output binary name
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o user-service ./cmd/user

# Stage 2: Runtime stage
# This stage creates the final, minimal image with just the compiled binary
FROM alpine:latest

# Install CA certificates for HTTPS connections
RUN apk --no-cache add ca-certificates

# Create a non-root user for security
# Running containers as root is a security risk
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Set working directory
WORKDIR /root/

# Copy the compiled binary from the builder stage
COPY --from=builder /app/user-service .

# Switch to non-root user
USER appuser

# Expose the port the service will run on
# This is just documentation - you still need to use -p flag when running
EXPOSE 8080

# Health check
# Kubernetes uses this to determine if the container is healthy
# It periodically calls this endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Command to run when the container starts
# This starts the user service
CMD ["./user-service"]

