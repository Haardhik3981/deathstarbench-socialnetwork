/**
 * K6 Stress Test for Social Network Application
 * 
 * Purpose: Find the breaking point of the system
 * Duration: ~15 minutes with aggressive ramp-up
 * 
 * Working Endpoints:
 * ✅ GET  /wrk2-api/home-timeline/read
 * ✅ GET  /wrk2-api/user-timeline/read  
 * ✅ POST /wrk2-api/post/compose
 * ✅ POST /wrk2-api/user/follow
 * 
 * Run: k6 run k6-stress-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const timeouts = new Counter('timeouts');
const requestDuration = new Trend('request_duration');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Stress test stages: aggressive ramp-up to find breaking point
export const options = {
  stages: [
    { duration: '1m', target: 50 },    // Warm up
    { duration: '2m', target: 100 },   // Normal load
    { duration: '2m', target: 200 },   // Above normal
    { duration: '2m', target: 300 },   // High load
    { duration: '2m', target: 400 },   // Very high load
    { duration: '2m', target: 500 },   // Breaking point?
    { duration: '2m', target: 600 },   // Beyond limits
    { duration: '2m', target: 0 },     // Recovery
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],  // Relaxed threshold for stress test
    errors: ['rate<0.5'],               // Allow higher error rate to find limits
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
  let endpointName;
  
  if (scenario < 0.4) {
    // ========== HOME TIMELINE (40%) ==========
    endpointName = 'HomeTimeline';
    response = http.get(
      `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${userId}&start=0&stop=10`,
      { timeout: '10s', tags: { name: endpointName } }
    );
  }
  
  else if (scenario < 0.7) {
    // ========== USER TIMELINE (30%) ==========
    endpointName = 'UserTimeline';
    response = http.get(
      `${BASE_URL}/wrk2-api/user-timeline/read?user_id=${userId}&start=0&stop=10`,
      { timeout: '10s', tags: { name: endpointName } }
    );
  }
  
  else if (scenario < 0.9) {
    // ========== COMPOSE POST (20%) ==========
    endpointName = 'ComposePost';
    const postText = randomString(100);
    response = http.post(
      `${BASE_URL}/wrk2-api/post/compose`,
      `user_id=${userId}&username=user_${userId}&text=${encodeURIComponent(postText)}&media_ids=[]&media_types=[]&post_type=0`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '10s',
        tags: { name: endpointName },
      }
    );
  }
  
  else {
    // ========== FOLLOW USER (10%) ==========
    endpointName = 'FollowUser';
    const followeeId = randomUserId();
    response = http.post(
      `${BASE_URL}/wrk2-api/user/follow`,
      `user_id=${userId}&followee_id=${followeeId}`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '10s',
        tags: { name: endpointName },
      }
    );
  }
  
  requestDuration.add(response.timings.duration);
  
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'no timeout': (r) => r.timings.duration < 10000,
  });
  
  if (!success) {
    errorRate.add(1);
    if (response.timings.duration >= 10000) {
      timeouts.add(1);
    }
  } else {
    errorRate.add(0);
  }
  
  // Minimal think time for stress test (more aggressive)
  sleep(0.3);
}

export function handleSummary(data) {
  const { metrics } = data;
  
  return {
    'stdout': `
================================================================================
                        🔥 STRESS TEST SUMMARY 🔥
================================================================================

📊 OVERALL RESULTS

Total Requests:      ${metrics.http_reqs?.values?.count || 0}
Failed Requests:     ${metrics.http_req_failed?.values?.count || 0}
Timeouts:            ${metrics.timeouts?.values?.count || 0}
Error Rate:          ${((metrics.errors?.values?.rate || 0) * 100).toFixed(2)}%

⏱️  RESPONSE TIMES

  - Average:         ${(metrics.http_req_duration?.values?.avg || 0).toFixed(2)} ms
  - Median (p50):    ${(metrics.http_req_duration?.values?.med || 0).toFixed(2)} ms
  - p95:             ${(metrics.http_req_duration?.values['p(95)'] || 0).toFixed(2)} ms
  - p99:             ${(metrics.http_req_duration?.values['p(99)'] || 0).toFixed(2)} ms
  - Max:             ${(metrics.http_req_duration?.values?.max || 0).toFixed(2)} ms

🚀 THROUGHPUT

  Peak Requests/sec: ${(metrics.http_reqs?.values?.rate || 0).toFixed(2)}
  Max Virtual Users: ${metrics.vus?.values?.max || 0}

================================================================================
                           ANALYSIS
================================================================================

📈 BREAKING POINT INDICATORS:

  ${((metrics.errors?.values?.rate || 0) * 100) > 10 ? '⚠️  ERROR RATE > 10%: System is overloaded!' : '✅ Error rate acceptable'}
  ${(metrics.http_req_duration?.values['p(99)'] || 0) > 2000 ? '⚠️  p99 > 2s: Response times degrading!' : '✅ Response times acceptable'}
  ${(metrics.timeouts?.values?.count || 0) > 0 ? '⚠️  TIMEOUTS DETECTED: System struggling!' : '✅ No timeouts'}

💡 RECOMMENDATIONS:

  - Check Grafana dashboard for CPU/Memory spikes
  - Review HPA scaling events
  - Identify bottleneck services

================================================================================
`,
    'stress-test-results.json': JSON.stringify(data, null, 2),
  };
}
