# Running k6 Load Tests

Now that your nginx-thrift gateway is working and accessible via port-forward, you can run load tests!

## Quick Start

### Option 1: Using Port-Forward (What You're Doing Now)

Since you're port-forwarding to `localhost:8080`, run:

```bash
cd /Users/fabricekurmann/Desktop/CS/School/CSE239/deathstarbench-socialnetwork/project

# In one terminal, keep the port-forward running:
kubectl port-forward svc/nginx-thrift-service 8080:8080

# In another terminal, run the k6 test:
BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh constant-load
```

### Option 2: Using LoadBalancer IP (If Available)

If your LoadBalancer service has an external IP:

```bash
# The script will auto-detect the IP
./scripts/run-k6-tests.sh constant-load

# Or manually set it:
BASE_URL=http://<LOADBALANCER_IP>:8080 ./scripts/run-k6-tests.sh constant-load
```

## Available Tests

1. **constant-load** - Steady load test (recommended to start with)
   ```bash
   BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh constant-load
   ```

2. **peak-test** - Sudden traffic spike
   ```bash
   BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh peak-test
   ```

3. **stress-test** - Gradual ramp-up to find breaking point
   ```bash
   BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh stress-test
   ```

4. **endurance-test** - Long-duration test (5+ hours)
   ```bash
   BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh endurance-test
   ```

5. **all** - Run all tests except endurance
   ```bash
   BASE_URL=http://localhost:8080 ./scripts/run-k6-tests.sh all
   ```

## What the Tests Do

The k6 tests simulate user workflows on the social network:

1. **Register a new user** (`POST /wrk2-api/user/register`)
2. **Compose a post** (`POST /wrk2-api/post/compose`)
3. **Read home timeline** (`GET /wrk2-api/home-timeline/read`)

### constant-load Test Details

- **Duration**: ~7 minutes total
  - 1 minute: Ramp up to 50 virtual users
  - 5 minutes: Maintain 50 users
  - 1 minute: Ramp down to 0
- **Thresholds** (test fails if not met):
  - 95% of requests < 1000ms
  - 99% of requests < 2000ms
  - Error rate < 5%
  - At least 10 requests/second

## Prerequisites

Make sure you have k6 installed:

```bash
# macOS
brew install k6

# Or download from: https://k6.io/docs/getting-started/installation/
```

## Results

Test results are saved to `k6-results/` directory:

- `constant-load_YYYYMMDD_HHMMSS.json` - Full results (JSON)
- `constant-load_YYYYMMDD_HHMMSS_summary.txt` - Summary statistics

## Troubleshooting

### Port-forward Connection Issues

If port-forward drops, restart it:
```bash
kubectl port-forward svc/nginx-thrift-service 8080:8080
```

### Getting LoadBalancer IP (Alternative)

Instead of port-forwarding, you can use the LoadBalancer IP directly:

```bash
# Check if LoadBalancer has an external IP
kubectl get svc nginx-thrift-service

# If it shows an EXTERNAL-IP, use that:
BASE_URL=http://<EXTERNAL-IP>:8080 ./scripts/run-k6-tests.sh constant-load
```

Note: LoadBalancer IPs can take 1-2 minutes to provision in GKE.

## Next Steps After Testing

After running k6 tests successfully:

1. **Review Results**: Check response times, error rates, throughput
2. **Monitor Resources**: Watch CPU/memory usage during tests
3. **Adjust Resources**: Scale up/down based on test results
4. **Set Up Autoscaling**: Configure HPA/VPA based on test findings
5. **Run Longer Tests**: Use endurance-test to find memory leaks or stability issues

## Example Output

```
[INFO] Using provided BASE_URL: http://localhost:8080
[INFO] Results will be saved to: k6-results
[INFO] Running constant-load...
[INFO] Target URL: http://localhost:8080

          /\      |‾‾| /‾‾/   /‾‾/
     /\  /  \     |  |/  /   /  /
    /  \/    \    |     (   /   ‾‾\
   /          \   |  |\  \ |  (‾)  |
  / __________ \  |__| \__\ \_____/ .io

  execution: local
     script: k6-tests/constant-load.js
     output: json=k6-results/constant-load_20231202_123456.json

  scenarios: (100.00%) 1 scenario, 50 max VUs, 7m0s max duration (incl. graceful stop):
           * default: Up to 50 looping VUs for 7m0s over 3 stages (gracefulRampDown: 30s, gracefulStop: 30s)
...
```

Happy testing! 🚀

