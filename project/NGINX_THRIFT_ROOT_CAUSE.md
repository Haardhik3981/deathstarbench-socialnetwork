# nginx-thrift Root Cause Analysis

## Problem

The nginx-thrift pod shows as `Running` but:
- Logs are empty
- Port-forwarding fails with "connection refused"
- nginx is not listening on port 8080

## Root Cause

The nginx.conf file is mounted at the **wrong path**!

### Current (WRONG):
- Mounted at: `/etc/nginx/nginx.conf`

### Should be (CORRECT):
- Mounted at: `/usr/local/openresty/nginx/conf/nginx.conf`

### Evidence

1. **Docker Compose** (`docker-compose.yml`):
   ```yaml
   volumes:
     - ./nginx-web-server/conf/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf
   ```

2. **Helm Chart** (`values.yaml`):
   ```yaml
   - name: nginx.conf
     mountPath: /usr/local/openresty/nginx/conf/nginx.conf
   ```

3. **OpenShift Deployment**:
   ```yaml
   - mountPath: /usr/local/openresty/nginx/conf/nginx.conf
   ```

## Why This Causes the Problem

1. OpenResty/nginx-thrift looks for config at `/usr/local/openresty/nginx/conf/nginx.conf`
2. Since it's not there, nginx never starts
3. Container stays running but nginx process doesn't exist
4. No logs because nginx never starts
5. Port 8080 not listening because nginx isn't running

## Solution

Update the deployment YAML to mount nginx.conf at the correct path:

```yaml
volumeMounts:
  - name: nginx-config
    mountPath: /usr/local/openresty/nginx/conf/nginx.conf  # FIXED PATH
    subPath: nginx.conf
    readOnly: true
```

## Additional Issues to Check

1. **Missing command/entrypoint**: The container may need an explicit command to start nginx
2. **Missing lua-thrift library**: May need to mount `/usr/local/openresty/lualib/thrift`
3. **ConfigMap may need lua-thrift**: Check if gen-lua needs special handling

## Next Steps

1. Run diagnostic script: `./scripts/deep-diagnose-nginx.sh`
2. Fix the mount path in `nginx-thrift-deployment.yaml`
3. Restart the deployment
4. Verify nginx starts and listens on port 8080

