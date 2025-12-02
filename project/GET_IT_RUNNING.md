# Get It Running - Simple Commands

## Just Run This:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# Apply the fixed deployment (lua-scripts temporarily disabled)
kubectl apply -f kubernetes/deployments/nginx-thrift-deployment.yaml

# Restart nginx
kubectl rollout restart deployment/nginx-thrift-deployment

# Wait 30 seconds
sleep 30

# Check if it's running
kubectl get pods -l app=nginx-thrift
```

If nginx-thrift shows `1/1 Running`, you're good!

Then check all pods:
```bash
kubectl get pods
```

All pods should be running now.

## What I Changed

- Temporarily disabled the lua-scripts mount in nginx-thrift deployment
- nginx will start without Lua scripts
- We can add them back later once everything else is working

## Next: Fix Lua Scripts (Later)

Once everything is running, we'll fix the lua-scripts ConfigMap properly. But for now, let's just get it deployed.

