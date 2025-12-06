# Stress Test Analysis - December 3, 2025

## Test Overview

- **Test Type:** Stress Test (Gradual Ramp-Up)
- **Duration:** 42 minutes 9.6 seconds
- **Test Start:** 2025-12-04T01:05:52Z (UTC)
- **Max Virtual Users:** 1,000
- **Total Iterations:** 217,806
- **Total Requests:** 226,973

---

## Executive Summary

⚠️ **CRITICAL ISSUES IDENTIFIED**

The system experienced significant degradation under stress, with multiple threshold violations:

1. **Latency exceeded acceptable limits** (p95: 10.11s, p99: 10.3s)
2. **High error rate** (24.49% - more than double the 10% threshold)
3. **User registration endpoint failure** (85% failure rate)
4. **System saturation** at ~90 req/s (well below expected capacity)

---

## Key Metrics

### Latency Metrics

| Percentile | Value | Threshold | Status |
|------------|-------|-----------|--------|
| **p50 (median)** | 82.85 ms | <500 ms | ✅ PASS |
| **p95** | **10.11 s** | <2 s | ❌ **FAIL** (5x over threshold) |
| **p99** | **10.3 s** | <5 s | ❌ **FAIL** (2x over threshold) |
| **Average** | 2.56 s | - | ⚠️ High |
| **Min** | 63.9 ms | - | ✅ Good |
| **Max** | 12.27 s | - | ⚠️ Very High |

**Analysis:**
- Median latency is excellent (82.85ms), indicating most requests are fast
- However, tail latency (p95/p99) is extremely high, suggesting:
  - **Bottleneck in specific operations** (likely user registration)
  - **Resource contention** under high load
  - **Possible database connection pool exhaustion**

### Throughput Metrics

| Metric | Value |
|--------|-------|
| **Total Requests** | 226,973 |
| **Requests/Second** | 89.73 req/s |
| **Successful Requests** | 162,658 (71.6%) |
| **Failed Requests** | 55,598 (24.49%) |

**Analysis:**
- Throughput of ~90 req/s is relatively low for a microservices architecture
- System appears to be **saturated** at this level
- Suggests a bottleneck preventing higher throughput

### Error Metrics

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| **Error Rate** | **24.49%** | <10% | ❌ **FAIL** |
| **Status 200** | 162,658 (71.6%) | - | ⚠️ Low |
| **Status 500** | 22,170 (9.8%) | - | ⚠️ High |
| **Status 400** | Unknown | - | - |
| **Other Errors** | 33,428 (14.7%) | - | ⚠️ High |

**Analysis:**
- Nearly 1 in 4 requests failed
- High 500 errors (9.8%) indicate server-side issues
- "Other" errors (14.7%) likely include timeouts and connection refused

---

## Endpoint-Specific Analysis

### User Registration (`/wrk2-api/user/register`)

| Metric | Value | Status |
|--------|-------|--------|
| **Success Rate** | **15%** | ❌ **CRITICAL** |
| **Successful** | 4,105 | - |
| **Failed** | 21,797 | - |
| **Response Time Check** | 15% passed | ❌ **FAIL** |

**Analysis:**
- **MAJOR BOTTLENECK:** User registration is the primary failure point
- Only 15% of registration attempts succeeded
- This is likely causing cascading failures:
  - Users can't register → can't create posts → can't read timelines
  - May be causing database connection pool exhaustion
  - Possible race conditions or locking issues

**Root Cause Hypotheses:**
1. **Database connection pool exhaustion** - Too many concurrent registration attempts
2. **Database locking** - User ID generation or uniqueness checks causing contention
3. **Resource limits** - user-service pods may be CPU/memory constrained
4. **No rate limiting** - Registration endpoint overwhelmed

### Follow Operation (`/wrk2-api/user/follow`)

| Metric | Value | Status |
|--------|-------|--------|
| **Success Rate** | **87%** | ⚠️ **MARGINAL** |
| **Successful** | 2,633 | - |
| **Failed** | 373 | - |

**Analysis:**
- Better than registration but still degraded
- 13% failure rate is concerning
- May be related to registration failures (can't follow users that don't exist)

### Compose Post (`/wrk2-api/post/compose`)

| Metric | Value | Status |
|--------|-------|--------|
| **Success Rate** | **100%** | ✅ **EXCELLENT** |
| **Response Time** | <2000ms | ✅ **PASS** |

**Analysis:**
- Compose endpoint performed well
- Suggests the issue is specific to user registration, not general system capacity

### Read Timeline (`/wrk2-api/home-timeline/read`)

| Metric | Value | Status |
|--------|-------|--------|
| **Success Rate** | **99%** | ✅ **GOOD** |
| **Response Time** | 99% <2000ms | ⚠️ **MARGINAL** |
| **Failed** | 70 out of 152,840 | - |

**Analysis:**
- Read operations are mostly successful
- Some latency issues (1% exceeded 2s threshold)
- Generally performing well despite system stress

---

## Performance Degradation Pattern

### Load Progression

The test gradually increased load from 10 to 1,000 VUs over 20 stages:

1. **Stages 1-3 (10-150 VUs):** Likely performed well
2. **Stages 4-6 (200-300 VUs):** Performance degradation began
3. **Stages 7-10 (400-700 VUs):** Significant degradation
4. **Stages 11-14 (800-1000 VUs):** System saturation reached
5. **Stage 15 (1000 VUs sustained):** Maintained at saturation level

### Key Observations

1. **Bimodal Performance:**
   - Fast operations (compose, timeline reads): ~138ms average
   - Slow operations (registration): Likely causing 10s+ delays

2. **Error Distribution:**
   - Most errors concentrated in registration endpoint
   - Other endpoints relatively stable

3. **Throughput Ceiling:**
   - System reached maximum throughput at ~90 req/s
   - Unable to scale beyond this point despite increasing load

---

## Root Cause Analysis

### Primary Bottleneck: User Registration

The user registration endpoint is the clear bottleneck. Possible causes:

1. **Database Contention:**
   - User ID generation (unique-id-service) may be a bottleneck
   - Database writes for user creation may be slow
   - Possible deadlocks or lock contention

2. **Resource Constraints:**
   - user-service pods may be CPU/memory constrained
   - Database connection pool may be exhausted
   - Network bandwidth may be saturated

3. **Architecture Issues:**
   - Synchronous operations blocking on database writes
   - No connection pooling or connection limits
   - Possible N+1 query problems

### Secondary Issues

1. **Autoscaling:**
   - System may not have scaled up fast enough
   - HPA may not be configured for latency-based scaling
   - Pod startup time may be too slow

2. **Database Performance:**
   - MongoDB may be overwhelmed
   - Indexes may be missing
   - Connection pool may be too small

---

## Recommendations

### Immediate Actions

1. **Investigate User Registration Endpoint:**
   ```bash
   # Check user-service logs during test period
   kubectl logs -l app=user-service --since-time="2025-12-04T01:05:52Z" | grep -i error
   
   # Check database connection pool usage
   # Query Prometheus for connection metrics during test
   ```

2. **Check Resource Utilization:**
   ```bash
   # Query Prometheus for CPU/memory during test period
   # Time range: 2025-12-04T01:05:52Z to 2025-12-04T01:47:52Z
   ```
   
   Prometheus queries:
   ```promql
   # CPU usage for user-service
   100 * rate(container_cpu_usage_seconds_total{pod=~"user-service.*"}[5m])
   
   # Memory usage
   container_memory_usage_bytes{pod=~"user-service.*"} / 1024 / 1024
   
   # Pod count
   count(kube_pod_info{pod=~"user-service.*"})
   ```

3. **Review Database Metrics:**
   - Check MongoDB connection pool usage
   - Review slow query logs
   - Check for lock contention

### Short-Term Fixes

1. **Increase User-Service Resources:**
   - Increase CPU/memory limits
   - Scale up replica count
   - Configure HPA for latency-based scaling

2. **Optimize Registration Endpoint:**
   - Add connection pooling
   - Implement rate limiting
   - Consider async processing for user creation
   - Add caching for user lookups

3. **Database Optimization:**
   - Increase connection pool size
   - Add indexes on frequently queried fields
   - Consider read replicas for user lookups

### Long-Term Improvements

1. **Architecture Changes:**
   - Implement async user registration (queue-based)
   - Add caching layer (Redis) for user data
   - Implement circuit breakers for failing services

2. **Monitoring & Alerting:**
   - Set up alerts for error rate >5%
   - Monitor latency percentiles (p95, p99)
   - Track database connection pool usage

3. **Load Testing:**
   - Run stress tests regularly
   - Establish performance baselines
   - Test autoscaling behavior

---

## Next Steps

1. **Query Prometheus for System Metrics:**
   - Time range: `2025-12-04T01:05:52Z` to `2025-12-04T01:47:52Z`
   - Check CPU, memory, pod count for all services
   - Identify which services were resource-constrained

2. **Review Service Logs:**
   - user-service logs (registration failures)
   - unique-id-service logs (ID generation)
   - Database logs (connection issues)

3. **Compare with Baseline:**
   - Run constant-load test to establish baseline
   - Compare metrics to identify degradation point

4. **Implement Fixes:**
   - Start with user-service resource increases
   - Optimize registration endpoint
   - Re-run stress test to validate improvements

---

## Metrics to Query in Prometheus

Use these queries with time range `2025-12-04T01:05:52Z` to `2025-12-04T01:47:52Z`:

```promql
# CPU usage by service
100 * rate(container_cpu_usage_seconds_total{pod=~"user-service.*"}[5m])
100 * rate(container_cpu_usage_seconds_total{pod=~"unique-id-service.*"}[5m])
100 * rate(container_cpu_usage_seconds_total{pod=~"compose-post-service.*"}[5m])

# Memory usage
container_memory_usage_bytes{pod=~"user-service.*"} / 1024 / 1024

# Pod count over time
count_over_time(kube_pod_info{pod=~"user-service.*"}[1m])

# Network I/O
rate(container_network_receive_bytes_total{pod=~"user-service.*"}[5m])
```

---

## Conclusion

The stress test revealed a **critical bottleneck in the user registration endpoint**, causing:
- 85% failure rate for registrations
- Overall 24.49% error rate
- Extreme tail latency (p95: 10.11s, p99: 10.3s)

The system is **saturated at ~90 req/s**, which is well below expected capacity. Immediate investigation and optimization of the user registration flow is required.

**Priority:** 🔴 **HIGH** - System cannot handle production load levels

