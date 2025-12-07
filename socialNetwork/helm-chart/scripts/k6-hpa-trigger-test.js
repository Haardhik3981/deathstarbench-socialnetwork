/**
 * K6 HPA Trigger Test for Social Network Application
 * 
 * Purpose: Generate HEAVY load to trigger HPA scaling
 * Target: Push CPU above 60% to trigger nginx-thrift HPA
 * 
 * This test is MORE AGGRESSIVE than stress test:
 * - Higher concurrent users (up to 800)
 * - Minimal think time (0.1s)
 * - Longer sustained high load
 * - Focus on CPU-intensive endpoints
 * 
 * Run locally:   k6 run k6-hpa-trigger-test.js
 * Run in cluster: kubectl apply -f k6-hpa-trigger-job.yaml -n cse239fall2025
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const requestsCompleted = new Counter('requests_completed');
const responseTime = new Trend('response_time');

// Configuration - nginx-thrift service URL
const BASE_URL = __ENV.BASE_URL || 'http://nginx-thrift:8080';

// HPA Trigger Test Profile - VERY AGGRESSIVE
export const options = {
  scenarios: {
    // Scenario 1: Sustained high load
    sustained_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 },   // Warm up to 100 users
        { duration: '1m', target: 200 },    // Ramp to 200 users
        { duration: '1m', target: 400 },    // Ramp to 400 users
        { duration: '2m', target: 600 },    // Ramp to 600 users - HEAVY LOAD
        { duration: '3m', target: 800 },    // MAXIMUM LOAD - 800 users for 3 min
        { duration: '2m', target: 800 },    // SUSTAIN 800 users
        { duration: '1m', target: 400 },    // Start cooling down
        { duration: '1m', target: 200 },    // Continue cooldown
        { duration: '1m', target: 0 },      // Ramp down to 0
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    // Relaxed thresholds - we WANT to stress the system
    http_req_duration: ['p(95)<5000'],  // Allow up to 5s response time
    errors: ['rate<0.8'],                // Allow up to 80% errors (system overload expected)
  },
  // Disable connection reuse to increase load
  noConnectionReuse: false,
  userAgent: 'K6-HPA-Trigger/1.0',
};

// Generate random user ID (1-962 based on dataset)
function randomUserId() {
  return Math.floor(Math.random() * 962) + 1;
}

// Generate random text
function randomText(length) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export default function () {
  const userId = randomUserId();
  const scenario = Math.random();
  
  // Distribution optimized for CPU load:
  // 40% - Home Timeline (read-heavy, exercises caching layer)
  // 30% - User Timeline (read-heavy)
  // 20% - Compose Post (write-heavy, CPU intensive)
  // 10% - Follow (graph operations)
  
  let response;
  
  if (scenario < 0.40) {
    // ========== HOME TIMELINE (40%) ==========
    response = http.get(
      `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${userId}&start=0&stop=20`,
      { 
        timeout: '10s',
        tags: { endpoint: 'home_timeline' } 
      }
    );
  }
  else if (scenario < 0.70) {
    // ========== USER TIMELINE (30%) ==========
    response = http.get(
      `${BASE_URL}/wrk2-api/user-timeline/read?user_id=${userId}&start=0&stop=20`,
      { 
        timeout: '10s',
        tags: { endpoint: 'user_timeline' } 
      }
    );
  }
  else if (scenario < 0.90) {
    // ========== COMPOSE POST (20%) - CPU INTENSIVE ==========
    const text = randomText(280); // Longer text = more processing
    response = http.post(
      `${BASE_URL}/wrk2-api/post/compose`,
      `user_id=${userId}&username=user_${userId}&text=${encodeURIComponent(text)}&media_ids=[]&media_types=[]&post_type=0`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '10s',
        tags: { endpoint: 'compose_post' },
      }
    );
  }
  else {
    // ========== FOLLOW USER (10%) ==========
    const followeeId = randomUserId();
    response = http.post(
      `${BASE_URL}/wrk2-api/user/follow`,
      `user_id=${userId}&followee_id=${followeeId}`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        timeout: '10s',
        tags: { endpoint: 'follow' },
      }
    );
  }
  
  // Track metrics
  responseTime.add(response.timings.duration);
  
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
  });
  
  if (success) {
    requestsCompleted.add(1);
    errorRate.add(0);
  } else {
    errorRate.add(1);
  }
  
  // MINIMAL think time - maximize load
  sleep(0.1);
}

// Lifecycle hooks
export function setup() {
  console.log('========================================');
  console.log('🔥 HPA TRIGGER TEST STARTING');
  console.log('========================================');
  console.log(`Target: ${BASE_URL}`);
  console.log('Duration: ~12 minutes');
  console.log('Max VUs: 800');
  console.log('');
  console.log('MONITOR HPA WITH:');
  console.log('  kubectl get hpa nginx-thrift -n cse239fall2025 -w');
  console.log('');
  console.log('WATCH PODS WITH:');
  console.log('  kubectl get pods -n cse239fall2025 -w | grep nginx-thrift');
  console.log('========================================');
}

export function teardown(data) {
  console.log('========================================');
  console.log('🏁 HPA TRIGGER TEST COMPLETE');
  console.log('========================================');
}

export function handleSummary(data) {
  const { metrics } = data;
  
  return {
    'stdout': `
================================================================================
                    🔥 HPA TRIGGER TEST RESULTS 🔥
================================================================================

📊 LOAD SUMMARY

Total Requests:        ${metrics.http_reqs?.values?.count || 0}
Successful Requests:   ${metrics.requests_completed?.values?.count || 0}
Error Rate:            ${((metrics.errors?.values?.rate || 0) * 100).toFixed(2)}%
Peak VUs:              ${metrics.vus?.values?.max || 0}
Test Duration:         ${(data.state?.testRunDurationMs / 1000 / 60).toFixed(2)} minutes

⏱️  RESPONSE TIMES

  Average:             ${(metrics.http_req_duration?.values?.avg || 0).toFixed(2)} ms
  Median (p50):        ${(metrics.http_req_duration?.values?.med || 0).toFixed(2)} ms
  p90:                 ${(metrics.http_req_duration?.values['p(90)'] || 0).toFixed(2)} ms
  p95:                 ${(metrics.http_req_duration?.values['p(95)'] || 0).toFixed(2)} ms
  p99:                 ${(metrics.http_req_duration?.values['p(99)'] || 0).toFixed(2)} ms
  Max:                 ${(metrics.http_req_duration?.values?.max || 0).toFixed(2)} ms

🚀 THROUGHPUT

  Requests/sec:        ${(metrics.http_reqs?.values?.rate || 0).toFixed(2)}
  Data received:       ${((metrics.data_received?.values?.count || 0) / 1024 / 1024).toFixed(2)} MB
  Data sent:           ${((metrics.data_sent?.values?.count || 0) / 1024 / 1024).toFixed(2)} MB

================================================================================
                         HPA SCALING CHECK
================================================================================

After this test, verify HPA scaled:

  kubectl get hpa nginx-thrift -n cse239fall2025
  kubectl describe hpa nginx-thrift -n cse239fall2025

Check scaling events:

  kubectl get events -n cse239fall2025 --field-selector reason=SuccessfulRescale

================================================================================
`,
    'hpa-trigger-results.json': JSON.stringify(data, null, 2),
  };
}
