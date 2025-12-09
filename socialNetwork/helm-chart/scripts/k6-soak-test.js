/**
 * K6 Soak Test for Social Network Application
 * 
 * Purpose: Test system stability over extended period
 *          Find memory leaks, resource exhaustion issues
 * Duration: 30 minutes at moderate load
 * 
 * Working Endpoints:
 * ✅ GET  /wrk2-api/home-timeline/read
 * ✅ GET  /wrk2-api/user-timeline/read  
 * ✅ POST /wrk2-api/post/compose
 * ✅ POST /wrk2-api/user/follow
 * 
 * Run: k6 run k6-soak-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const requestDuration = new Trend('request_duration');
const successfulRequests = new Counter('successful_requests');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Soak test: sustained moderate load over extended period
export const options = {
  stages: [
    { duration: '2m', target: 75 },    // Ramp up
    { duration: '26m', target: 75 },   // Sustained load for 26 minutes
    { duration: '2m', target: 0 },     // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    errors: ['rate<0.05'],  // Strict: < 5% errors over long period
  },
};

function randomUserId() {
  return Math.floor(Math.random() * 962) + 1;
}

function randomString(length) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export default function () {
  const userId = randomUserId();
  const scenario = Math.random();
  
  let response;
  
  if (scenario < 0.5) {
    // ========== HOME TIMELINE (50%) ==========
    response = http.get(
      `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${userId}&start=0&stop=10`,
      { timeout: '30s', tags: { name: 'HomeTimeline' } }
    );
  }
  
  else if (scenario < 0.8) {
    // ========== USER TIMELINE (30%) ==========
    response = http.get(
      `${BASE_URL}/wrk2-api/user-timeline/read?user_id=${userId}&start=0&stop=10`,
      { timeout: '30s', tags: { name: 'UserTimeline' } }
    );
  }
  
  else if (scenario < 0.95) {
    // ========== COMPOSE POST (15%) ==========
    const postText = randomString(100);
    response = http.post(
      `${BASE_URL}/wrk2-api/post/compose`,
      `user_id=${userId}&username=user_${userId}&text=${encodeURIComponent(postText)}&media_ids=[]&media_types=[]&post_type=0`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '30s',
        tags: { name: 'ComposePost' },
      }
    );
  }
  
  else {
    // ========== FOLLOW USER (5%) ==========
    const followeeId = randomUserId();
    response = http.post(
      `${BASE_URL}/wrk2-api/user/follow`,
      `user_id=${userId}&followee_id=${followeeId}`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '30s',
        tags: { name: 'FollowUser' },
      }
    );
  }
  
  requestDuration.add(response.timings.duration);
  
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response time OK': (r) => r.timings.duration < 1000,
  });
  
  if (success) {
    successfulRequests.add(1);
  }
  errorRate.add(!success);
  
  // Normal think time for soak test
  sleep(Math.random() * 3 + 1); // 1-4 seconds
}

export function handleSummary(data) {
  const { metrics } = data;
  const durationMinutes = (data.state?.testRunDurationMs / 1000 / 60).toFixed(2);
  
  return {
    'stdout': `
================================================================================
                     ⏱️  SOAK TEST SUMMARY ⏱️
================================================================================

Test Duration:       ${durationMinutes} minutes

📊 OVERALL RESULTS

Total Requests:      ${metrics.http_reqs?.values?.count || 0}
Successful:          ${metrics.successful_requests?.values?.count || 0}
Error Rate:          ${((metrics.errors?.values?.rate || 0) * 100).toFixed(4)}%

⏱️  RESPONSE TIMES

  - Average:         ${(metrics.http_req_duration?.values?.avg || 0).toFixed(2)} ms
  - Median (p50):    ${(metrics.http_req_duration?.values?.med || 0).toFixed(2)} ms
  - p95:             ${(metrics.http_req_duration?.values['p(95)'] || 0).toFixed(2)} ms
  - p99:             ${(metrics.http_req_duration?.values['p(99)'] || 0).toFixed(2)} ms
  - Max:             ${(metrics.http_req_duration?.values?.max || 0).toFixed(2)} ms

🚀 THROUGHPUT

  Requests/sec:      ${(metrics.http_reqs?.values?.rate || 0).toFixed(2)}
  Virtual Users:     ${metrics.vus?.values?.max || 0}

================================================================================
                        STABILITY ANALYSIS
================================================================================

🔍 WHAT TO CHECK IN GRAFANA:

  1. Memory Usage Over Time:
     - Should be STABLE (no continuous growth)
     - Growth indicates memory leak
  
  2. CPU Usage Over Time:
     - Should be STABLE around same level
     - Spikes indicate inefficient processing
  
  3. Response Time Trend:
     - p95/p99 should NOT increase over time
     - Increasing latency = resource exhaustion

  4. Error Rate Trend:
     - Should stay near 0%
     - Increasing errors = system degrading

================================================================================
`,
    'soak-test-results.json': JSON.stringify(data, null, 2),
  };
}
