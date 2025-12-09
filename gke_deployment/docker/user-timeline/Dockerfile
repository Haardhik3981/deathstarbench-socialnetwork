# Dockerfile for User Timeline Service
#
# WHAT THIS DOES:
# This Dockerfile packages the User Timeline microservice, which manages user activity
# timelines (e.g., posts, updates, activities that appear on a user's timeline).
#
# This is a template - adapt based on DeathStarBench's actual implementation.

# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git ca-certificates

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o user-timeline-service ./cmd/user-timeline

# Runtime stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /root/

COPY --from=builder /app/user-timeline-service .

USER appuser

# User Timeline service typically runs on port 9091
EXPOSE 9091

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:9091/health || exit 1

CMD ["./user-timeline-service"]

