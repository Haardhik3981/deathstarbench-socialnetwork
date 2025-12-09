/**
 * K6 Spike Test for Social Network Application
 * 
 * Purpose: Test system response to sudden traffic spikes
 * Duration: ~10 minutes with sudden load increases
 * 
 * Working Endpoints:
 * ✅ GET  /wrk2-api/home-timeline/read
 * ✅ GET  /wrk2-api/user-timeline/read  
 * ✅ POST /wrk2-api/post/compose
 * ✅ POST /wrk2-api/user/register
 * ✅ POST /wrk2-api/user/follow
 * ✅ POST /wrk2-api/user/unfollow
 * 
 * Run: k6 run k6-spike-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const requestDuration = new Trend('request_duration');
const successfulRequests = new Counter('successful_requests');
const spikeSurvivalRate = new Rate('spike_survival');

// Configuration
const BASE_URL = 'http://nginx-thrift:8080';

// Spike test stages: sudden load increases and drops
export const options = {
  stages: [
    { duration: '1m', target: 50 },    // Normal load
    { duration: '10s', target: 300 },  // SPIKE! 6x increase
    { duration: '1m', target: 300 },   // Sustain spike
    { duration: '10s', target: 50 },   // Drop back
    { duration: '1m', target: 50 },    // Recover
    { duration: '10s', target: 400 },  // BIGGER SPIKE! 8x increase
    { duration: '1m', target: 400 },   // Sustain bigger spike
    { duration: '10s', target: 50 },   // Drop back
    { duration: '1m', target: 50 },    // Recover
    { duration: '10s', target: 500 },  // MASSIVE SPIKE! 10x increase
    { duration: '1m', target: 500 },   // Sustain massive spike
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<3000'],  // Relaxed for spike test
    errors: ['rate<0.3'],               // Allow 30% errors during spikes
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
  
  if (scenario < 0.4) {
    // Home Timeline (40%)
    response = http.get(
      `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${userId}&start=0&stop=10`,
      { timeout: '10s', tags: { name: 'HomeTimeline' } }
    );
  }
  else if (scenario < 0.7) {
    // User Timeline (30%)
    response = http.get(
      `${BASE_URL}/wrk2-api/user-timeline/read?user_id=${userId}&start=0&stop=10`,
      { timeout: '10s', tags: { name: 'UserTimeline' } }
    );
  }
  else if (scenario < 0.85) {
    // Compose Post (15%)
    const postText = randomString(100);
    response = http.post(
      `${BASE_URL}/wrk2-api/post/compose`,
      `user_id=${userId}&username=user_${userId}&text=${encodeURIComponent(postText)}&media_ids=[]&media_types=[]&post_type=0`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '10s',
        tags: { name: 'ComposePost' },
      }
    );
  }
  else if (scenario < 0.95) {
    // Follow User (10%)
    const followeeId = randomUserId();
    response = http.post(
      `${BASE_URL}/wrk2-api/user/follow`,
      `user_id=${userId}&followee_id=${followeeId}`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '10s',
        tags: { name: 'FollowUser' },
      }
    );
  }
  else {
    // Register User (5%)
    const newUserId = Math.floor(Math.random() * 100000) + 10000;
    const username = `testuser_${newUserId}`;
    response = http.post(
      `${BASE_URL}/wrk2-api/user/register`,
      `first_name=Test&last_name=User&username=${username}&password=testpass&user_id=${newUserId}`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '10s',
        tags: { name: 'RegisterUser' },
      }
    );
  }
  
  requestDuration.add(response.timings.duration);
  
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'no timeout': (r) => r.timings.duration < 10000,
  });
  
  if (success) {
    successfulRequests.add(1);
    spikeSurvivalRate.add(1);
  } else {
    spikeSurvivalRate.add(0);
  }
  
  errorRate.add(!success);
  
  // Minimal think time for spike test
  sleep(0.1);
}

export function handleSummary(data) {
  const { metrics } = data;
  
  return {
    'stdout': `
================================================================================
                     🚀 SPIKE TEST SUMMARY 🚀
================================================================================

Test Duration:       ${(data.state?.testRunDurationMs / 1000 / 60).toFixed(2)} minutes

📊 OVERALL RESULTS

Total Requests:      ${metrics.http_reqs?.values?.count || 0}
Successful:          ${metrics.successful_requests?.values?.count || 0}
Failed:              ${(metrics.http_reqs?.values?.count || 0) - (metrics.successful_requests?.values?.count || 0)}
Error Rate:          ${((metrics.errors?.values?.rate || 0) * 100).toFixed(2)}%
Spike Survival:      ${((metrics.spike_survival?.values?.rate || 0) * 100).toFixed(2)}%

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
                        SPIKE ANALYSIS
================================================================================

🎯 SPIKE PERFORMANCE:

  Spike 1 (50→300 users):   ${((metrics.spike_survival?.values?.rate || 0) * 100) > 70 ? '✅ System handled spike well' : '⚠️  System struggled with spike'}
  Spike 2 (50→400 users):   Check response time degradation
  Spike 3 (50→500 users):   Check for failures and timeouts

💡 KEY INDICATORS:

  ${((metrics.errors?.values?.rate || 0) * 100) < 15 ? '✅ Good spike resilience (< 15% errors)' : '⚠️  Poor spike resilience (> 15% errors)'}
  ${(metrics.http_req_duration?.values['p(99)'] || 0) < 5000 ? '✅ Latency acceptable under spikes' : '⚠️  High latency during spikes'}
  
📈 RECOMMENDATIONS:

  - Review Grafana for CPU/Memory spikes
  - Check if HPA scaling triggered
  - Identify services that throttled
  - Consider circuit breakers for sudden load

================================================================================
`,
    'spike-test-results.json': JSON.stringify(data, null, 2),
  };
}

