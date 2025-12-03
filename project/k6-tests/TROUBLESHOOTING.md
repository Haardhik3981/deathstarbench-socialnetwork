# k6 Test Troubleshooting Guide

## Issue: 100% Request Failure Rate

### Symptoms
- All requests failing (`http_req_failed: 100.00%`)
- `register status is 200` check: 0% success (0 out of 13,922)
- Response times are reasonable (~295ms average), indicating requests are reaching the server
- Threshold violation: `✗ 'rate<0.05' rate=100.00%`

### Root Cause

The k6 test script was sending **JSON data** (`Content-Type: application/json`), but the DeathStarBench social network endpoints expect **form-encoded data** (`Content-Type: application/x-www-form-urlencoded`).

The nginx Lua handlers use `ngx.req.get_post_args()` which only works with form-encoded POST data, not JSON. When JSON is sent:
- The Lua script can't parse the fields
- It returns HTTP 400 (Bad Request) with "Incomplete arguments"
- All requests fail

### Solution

The test script has been updated to:
1. **Encode data as form-encoded** using `application/x-www-form-urlencoded`
2. **Set the correct Content-Type header** in requests
3. **Add error logging** to help debug future issues (logs ~1% of errors to avoid spam)

### What Changed

**Before:**
```javascript
const registerResponse = http.post(
  `${BASE_URL}/wrk2-api/user/register`,
  registerPayload,  // Sent as JSON
  { tags: { name: 'RegisterUser' } }
);
```

**After:**
```javascript
const registerResponse = http.post(
  `${BASE_URL}/wrk2-api/user/register`,
  encodeFormData(registerPayload),  // Sent as form-encoded
  {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    tags: { name: 'RegisterUser' }
  }
);
```

### Expected Results After Fix

After running the test again, you should see:
- ✅ `http_req_failed` rate < 5% (threshold: `rate<0.05`)
- ✅ `register status is 200` check passing
- ✅ Successful user registrations and post compositions
- ✅ Home timeline reads working

### Testing the Fix

Run the test again:
```bash
BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh constant-load
```

### Additional Debugging

If you still see errors after the fix:

1. **Check the actual error responses:**
   - The script now logs sample error responses (status code and body)
   - Look for patterns in the error messages

2. **Verify the service is running:**
   ```bash
   kubectl get pods -l app=nginx-thrift
   kubectl logs -l app=nginx-thrift --tail=50
   ```

3. **Test a single request manually:**
   ```bash
   curl -X POST http://localhost:8080/wrk2-api/user/register \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "user_id=123&username=testuser&first_name=Test&last_name=User&password=testpass"
   ```
   
   Expected response: `Success!`

4. **Check service connectivity:**
   ```bash
   # Check if user-service is reachable from nginx-thrift
   kubectl exec -it <nginx-thrift-pod> -- curl http://user-service:9090
   ```

### Common Issues

1. **Service not ready:** Wait for all pods to be `Running` and `Ready`
2. **Port-forward dropped:** Restart `kubectl port-forward svc/nginx-thrift-service 8080:8080`
3. **Database not initialized:** Some services may need database initialization
4. **Resource constraints:** Check if pods are being OOMKilled or CPU throttled

### Understanding the Test Output

**Good output indicators:**
- `http_req_failed: < 5%`
- `checks_succeeded: > 95%`
- `http_req_duration: p(95) < 1000ms`
- All thresholds passing (✓)

**Warning signs:**
- High error rates (> 5%)
- Increasing response times over test duration
- Many failed checks
- Threshold violations (✗)

