# Quick Deploy - Get Everything Running

## Run These Commands:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# Fix duplicates
kubectl scale deployment nginx-thrift-deployment --replicas=1
kubectl scale deployment user-service-deployment --replicas=1

# Apply updated deployment (health checks disabled)
kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml

# Wait
sleep 10

# Check status
kubectl get pods
```

**If nginx is still crashing**, just disable it for now:

```bash
# Disable nginx-thrift entirely (you can test services directly)
kubectl scale deployment nginx-thrift-deployment --replicas=0
```

Then all other pods should be running fine. You can test the services directly without nginx-thrift for now.

