# Dockerfile for Social Graph Service
#
# WHAT THIS DOES:
# This Dockerfile packages the Social Graph microservice, which manages friend
# connections and social relationships between users (e.g., who follows whom).
#
# This is a template - adapt based on DeathStarBench's actual implementation.
# The Social Graph service is often written in Go or C++ for performance.

# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git ca-certificates

# Copy dependency files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
# The -ldflags flag strips debug information to reduce binary size
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o social-graph-service ./cmd/social-graph

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /root/

# Copy binary from builder
COPY --from=builder /app/social-graph-service .

USER appuser

# Social Graph service typically runs on port 9090
EXPOSE 9090

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:9090/health || exit 1

CMD ["./social-graph-service"]

