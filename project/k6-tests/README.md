# k6 Load Tests for DeathStarBench Social Network

This directory contains k6 load test scripts for testing the DeathStarBench social network deployment on GKE.

## Test Files

### ✅ `constant-load.js` - **Ready to Use**
- **Purpose**: Baseline performance testing with steady load
- **Duration**: ~3 minutes
- **Load**: 50 VUs, constant
- **Endpoints**: Uses correct `wrk2-api` endpoints
- **Features**: Includes follower relationship fix to avoid "ZADD: no key specified" errors
- **Status**: ✅ Fully functional and tested

### ✅ `peak-test.js` - **Ready to Use**
- **Purpose**: Traffic spike testing with gradual ramp-up
- **Duration**: ~10 minutes
- **Load**: 50 → 400 VUs (gradual spike over 2m) → 100 → 50 VUs
- **Endpoints**: Uses correct `wrk2-api` endpoints
- **Features**: Includes follower relationship fix
- **Status**: ✅ Updated based on sweet-test results
- **Note**: Adjusted from 1000 VUs to 400 VUs for achievable load that triggers autoscaling

### ✅ `sweet-test.js` - **Recommended for Autoscaling Demo** ⭐
- **Purpose**: Demonstrates autoscaling under challenging but achievable load
- **Duration**: ~9 minutes
- **Load**: 50 → 200 → 350 VUs (gradual ramp) → 150 → 50 VUs
- **Endpoints**: Uses correct `wrk2-api` endpoints
- **Features**: Includes follower relationship fix
- **Status**: ✅ Fully functional and tested
- **Best for**: Proving autoscaling works without overwhelming the system
- **Expected**: >85% success rate, clear autoscaling behavior visible

### ✅ `stress-test.js` - **Ready to Use**
- **Purpose**: Gradual ramp-up to find breaking point
- **Duration**: ~35 minutes
- **Load**: 10 → 400 VUs (gradual increase, 2m per stage)
- **Endpoints**: Uses correct `wrk2-api` endpoints
- **Features**: Includes follower relationship fix
- **Status**: ✅ Updated based on sweet-test results
- **Note**: Adjusted from 1000 VUs to 400 VUs peak for achievable stress testing

### ✅ `endurance-test.js` - **Ready to Use**
- **Purpose**: Long-duration testing for memory leaks and stability
- **Duration**: ~2.5 hours (reduced from 5h for practicality)
- **Load**: Gradual ramp to 200 VUs, sustained for 2 hours
- **Endpoints**: Uses correct `wrk2-api` endpoints
- **Features**: Includes follower relationship fix
- **Status**: ✅ Updated based on sweet-test results
- **Note**: Increased load from 100 to 200 VUs for more challenging endurance test

### `test-helpers.js` - Shared Helper Functions
- Contains reusable functions for all tests
- Includes: `registerUser()`, `ensureUserHasFollower()`, `setupSeedUser()`, etc.
- Used by all test scripts

### `test-endpoint.sh` - Quick Endpoint Test
- Simple bash script to test a single endpoint
- Useful for quick verification

## Quick Start

### Prerequisites
1. **k6 installed**: `brew install k6` (macOS) or [download](https://k6.io/docs/getting-started/installation/)
2. **Port-forward running**: `kubectl port-forward svc/nginx-thrift 8080:8080`
3. **Deployment ready**: All pods running (verify with `./scripts/verify-deployment.sh`)

### Run Tests

```bash
# Constant load test (recommended first)
k6 run k6-tests/constant-load.js

# Peak/spike test (very aggressive)
k6 run k6-tests/peak-test.js

# Sweet spot test (recommended for autoscaling demo)
k6 run k6-tests/sweet-test.js

# Stress test (gradual ramp-up)
k6 run k6-tests/stress-test.js

# Endurance test (5+ hours - run only when needed)
k6 run k6-tests/endurance-test.js
```

### With Custom BASE_URL

```bash
BASE_URL=http://localhost:8080 k6 run k6-tests/constant-load.js
```

## Test Details

### Constant Load Test
- **Best for**: Establishing baseline performance
- **What it tests**: System stability under steady load
- **Expected results**: Low error rate (<5%), consistent latency

### Peak Test
- **Best for**: Testing extreme spike handling
- **What it tests**: How system handles sudden extreme load increases (1000 VUs)
- **Expected results**: High failure rate (50-60%) is normal, system should recover
- **Note**: Very aggressive - use for stress testing, not for demonstrating autoscaling

### Sweet Test ⭐ **Recommended**
- **Best for**: Demonstrating autoscaling effectiveness
- **What it tests**: Gradual load increase to challenging but achievable level (350 VUs)
- **Expected results**: >85% success rate, clear autoscaling behavior, good performance
- **Why it's better**: More realistic load, proves autoscaling works without system failure

### Stress Test
- **Best for**: Finding maximum capacity and bottlenecks
- **What it tests**: Gradual load increase to find breaking point
- **Expected results**: Latency increases as load increases, identify where system fails

### Endurance Test
- **Best for**: Long-term stability and memory leak detection
- **What it tests**: System behavior over extended period
- **Expected results**: Stable performance over time, no memory leaks

## Key Features

### Follower Relationship Fix
All tests include a fix to avoid the "ZADD: no key specified" error:
- Creates a seed user (user_id 1) in setup
- Ensures new users have at least one follower before composing posts
- This prevents Redis errors when users have no followers

### Correct Endpoints
All tests use the correct `wrk2-api` endpoints:
- `/wrk2-api/user/register` - User registration
- `/wrk2-api/user/follow` - Follow relationships
- `/wrk2-api/post/compose` - Compose posts
- `/wrk2-api/home-timeline/read` - Read home timeline
- `/wrk2-api/user-timeline/read` - Read user timeline

### Status Code Tracking
All tests track HTTP status codes:
- 200 OK
- 400 Bad Request
- 500+ Server Error
- Other (timeouts, connection refused, etc.)

## Understanding Results

### Expected vs Critical Errors

**Expected Errors (Normal under load):**
- High failure rate during extreme load (1000+ VUs)
- Connection timeouts/refused (status_other)
- High latency during spikes
- Some endpoint degradation under extreme load

**Critical Errors (Need investigation):**
- High 500 errors (services crashing)
- Low success rate on compose/timeline endpoints (<80%)
- Services not recovering after load decreases
- Memory leaks (gradual increase over time)

### Analysis Script

Use the analysis script to understand test results:

```bash
./scripts/analyze-peak-test-results.sh
```

## Test Workflow

Each test iteration typically:
1. **Register** a new user
2. **Follow** - Create follower relationship (seed user follows new user)
3. **Compose** a post (now safe - user has a follower)
4. **Read** home timeline

This workflow ensures:
- Tests use real user workflows
- No "ZADD: no key specified" errors
- Realistic load patterns

## Tips

1. **Start with constant-load**: Establish baseline before running stress tests
2. **Monitor during tests**: Watch Prometheus/Grafana for resource usage
3. **Check pod status**: `kubectl get pods` during tests
4. **Review logs**: Check service logs if errors are high
5. **Endurance test**: Only run when you have time (5+ hours)

## Troubleshooting

### Tests Failing with 100% Error Rate
- Check if port-forward is running: `lsof -i :8080`
- Verify deployment: `./scripts/verify-deployment.sh`
- Check nginx-thrift logs: `kubectl logs -l app=nginx-thrift --tail=100`

### High Error Rate During Spike
- **Expected**: Spike tests (1000 VUs) will have high error rates
- **Normal**: 80-90% failure rate during extreme spikes is normal
- **Check**: Look at compose/timeline success rates (should be >95%)

### Status Counters Show 0
- This is a known k6 limitation - counters may not be readable in teardown
- Check the CUSTOM metrics section for actual counts
- The summary section shows the real numbers

## Files

- `constant-load.js` - Constant load test (3 min)
- `peak-test.js` - Extreme spike test (7 min) - Very aggressive
- `sweet-test.js` - Sweet spot test (9 min) - ⭐ Recommended for autoscaling demo
- `stress-test.js` - Gradual ramp-up test (40+ min)
- `endurance-test.js` - Long-duration test (5+ hours)
- `test-helpers.js` - Shared helper functions
- `test-endpoint.sh` - Quick endpoint test script
- `README.md` - This file

