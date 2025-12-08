# k6 Load Tests

This directory contains k6 load testing scripts for the DeathStarBench Social Network deployment.

## Test Scripts

### Core Tests

| File | Purpose | Duration | Peak VUs | Use Case |
|------|---------|----------|----------|----------|
| `quick-test.js` | Quick validation | ~20s | 10 | Verify system works |
| `constant-load.js` | Baseline performance | ~3 min | 50 | Steady load testing |
| `sweet-test.js` | ⭐ Autoscaling demo | ~9 min | 350 | Recommended for HPA demo |
| `peak-test.js` | Traffic spike | ~10 min | 400 | Extreme load testing |
| `stress-test.js` | Gradual ramp-up | ~35 min | 400 | Find breaking points |
| `cpu-intensive-test.js` | ⭐ CPU-focused load | ~20 min | 1000 | Force CPU-based scaling |
| `endurance-test.js` | Long duration | ~2.5 hours | 200 | Stability & memory leaks |
| `vpa-learning-test.js` | ⭐ VPA learning | ~19.5 min | 200 | VPA autoscaling test |

### Helper Files

| File | Purpose |
|------|---------|
| `test-helpers.js` | Shared functions (user registration, post generation, etc.) |
| `test-endpoint.sh` | Quick endpoint validation script |
| `CPU_INTENSIVE_VS_STRESS_COMPARISON.md` | Comparison of CPU-intensive vs stress tests |

## Quick Start

### Prerequisites
- k6 installed: `brew install k6` (macOS) or [download](https://k6.io/docs/getting-started/installation/)
- Port-forward running: `kubectl port-forward svc/nginx-thrift-service 8080:8080`
- System verified: `./scripts/verify-system-ready.sh`

### Run Tests

```bash
# Using the test runner (recommended)
./scripts/run-test-with-metrics.sh <test-name>

# Direct k6 execution
k6 run k6-tests/sweet-test.js

# With custom URL
BASE_URL=http://localhost:8080 k6 run k6-tests/constant-load.js
```

### Recommended Tests

**For HPA Autoscaling Demo:**
```bash
./scripts/run-test-with-metrics.sh sweet-test
```

**For CPU-Based Scaling:**
```bash
./scripts/run-test-with-metrics.sh cpu-intensive-test
```

**For VPA Testing:**
```bash
./scripts/run-test-with-metrics.sh vpa-learning-test
```

## Test Details

### quick-test.js
- **Purpose**: Fast system validation
- **Load**: 10 VUs, 20 seconds
- **Best for**: Quick health check

### constant-load.js
- **Purpose**: Baseline performance measurement
- **Load**: 50 VUs, constant
- **Best for**: Establishing performance baseline

### sweet-test.js ⭐
- **Purpose**: Demonstrates autoscaling effectively
- **Load**: 50 → 200 → 350 VUs (gradual ramp)
- **Best for**: Proving autoscaling works without overwhelming system
- **Expected**: >85% success rate, clear scaling behavior

### peak-test.js
- **Purpose**: Extreme traffic spike testing
- **Load**: 50 → 400 VUs (sudden spike)
- **Best for**: Testing system limits
- **Note**: High failure rates expected

### stress-test.js
- **Purpose**: Gradual ramp-up to find breaking points
- **Load**: 10 → 400 VUs (gradual increase)
- **Best for**: Identifying bottlenecks and maximum capacity

### cpu-intensive-test.js ⭐
- **Purpose**: Force CPU-based HPA scaling
- **Load**: 10 → 1000 VUs (aggressive ramp)
- **Best for**: Testing CPU-based autoscaling (with reduced CPU requests)
- **Features**: Large payloads, multiple operations, reduced think time

### endurance-test.js
- **Purpose**: Long-term stability testing
- **Load**: Gradual ramp to 200 VUs, sustained 2 hours
- **Best for**: Memory leak detection, stability validation

### vpa-learning-test.js ⭐
- **Purpose**: Help VPA learn resource usage patterns
- **Load**: 50 → 120 VUs (12 min warmup) → 200 VUs
- **Best for**: VPA autoscaling experiments
- **Note**: VPA needs historical data to make recommendations

## Test Workflow

Each test typically:
1. Registers new users
2. Creates follower relationships
3. Composes posts
4. Reads timelines

All tests use the `wrk2-api` endpoints and include fixes to prevent Redis errors.

## Results

Test results are saved to `k6-results/` with timestamps:
- `{test-name}_{timestamp}.json` - Full k6 JSON output
- `{test-name}_{timestamp}_summary.txt` - Human-readable summary
- `{test-name}_{timestamp}_metrics.txt` - Extracted metrics

## See Also

- `scripts/run-test-with-metrics.sh` - Test runner with metrics extraction
- `scripts/extract-k6-metrics.sh` - Metrics extraction utility
- `TESTERS_MANUAL.md` - Comprehensive testing guide
