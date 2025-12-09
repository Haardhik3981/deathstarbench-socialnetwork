# Dockerfile for Nginx Reverse Proxy
# 
# WHAT THIS DOES:
# This Dockerfile creates a container image for Nginx, which acts as a reverse proxy
# and load balancer in front of our microservices. It receives incoming HTTP requests
# and routes them to the appropriate backend service based on URL paths.
#
# WHY WE NEED IT:
# In a microservice architecture, we need a single entry point that can route requests
# to different services. Nginx handles this routing efficiently and can also provide
# load balancing across multiple instances of the same service.

# Use the official Nginx image as our base
# Alpine Linux is a minimal Linux distribution, making the image smaller and faster to pull
FROM nginx:alpine

# Set working directory inside the container
WORKDIR /etc/nginx

# Copy our custom Nginx configuration file
# This file defines how Nginx should route requests to different microservices
COPY nginx.conf /etc/nginx/nginx.conf

# Expose port 80 - this is the standard HTTP port
# When a container runs, this port will be accessible from outside
EXPOSE 80

# Start Nginx when the container starts
# The 'daemon off' flag runs Nginx in the foreground (required for Docker)
CMD ["nginx", "-g", "daemon off;"]

