/**
 * K6 Load Test for Social Network Application
 * 
 * Purpose: Test normal expected load conditions
 * Duration: ~14 minutes with gradual ramp-up
 * 
 * Working Endpoints:
 * ✅ GET  /wrk2-api/home-timeline/read
 * ✅ GET  /wrk2-api/user-timeline/read  
 * ✅ POST /wrk2-api/post/compose
 * ✅ POST /wrk2-api/user/register
 * ✅ POST /wrk2-api/user/follow
 * ✅ POST /wrk2-api/user/unfollow
 * 
 * Run: k6 run k6-load-test.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const homeTimelineDuration = new Trend('home_timeline_duration');
const userTimelineDuration = new Trend('user_timeline_duration');
const composePostDuration = new Trend('compose_post_duration');
const followDuration = new Trend('follow_duration');
const successfulRequests = new Counter('successful_requests');

// Configuration - Update this to your service URL
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Load test stages: gradual ramp-up, sustained load, ramp-down
export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp up to 50 users over 2 minutes
    { duration: '5m', target: 50 },   // Stay at 50 users for 5 minutes
    { duration: '2m', target: 100 },  // Ramp up to 100 users
    { duration: '3m', target: 100 },  // Stay at 100 users for 3 minutes
    { duration: '2m', target: 0 },    // Ramp down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'], // 95% < 500ms, 99% < 1s
    errors: ['rate<0.1'],                           // Error rate < 10%
  },
  // Connection settings for better stability with port-forward
  noConnectionReuse: false,
  userAgent: 'K6LoadTest/1.0',
};

// Generate random user ID (1-962 based on Social Network dataset)
function randomUserId() {
  return Math.floor(Math.random() * 962) + 1;
}

// Generate random string for post content
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
  
  // Scenario distribution:
  // 35% - Read Home Timeline
  // 30% - Read User Timeline
  // 15% - Compose Post
  // 10% - Follow User
  // 5%  - Unfollow User
  // 5%  - Register User
  
  if (scenario < 0.35) {
    // ========== READ HOME TIMELINE (40%) ==========
    const res = http.get(
      `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${userId}&start=0&stop=10`,
      { tags: { name: 'HomeTimeline' } }
    );
    
    homeTimelineDuration.add(res.timings.duration);
    
    const success = check(res, {
      'home timeline status is 200': (r) => r.status === 200,
      'home timeline response time < 500ms': (r) => r.timings.duration < 500,
    });
    
    if (success) successfulRequests.add(1);
    errorRate.add(!success);
  }
  
  else if (scenario < 0.65) {
    // ========== READ USER TIMELINE (30%) ==========
    const targetUserId = randomUserId();
    const res = http.get(
      `${BASE_URL}/wrk2-api/user-timeline/read?user_id=${targetUserId}&start=0&stop=10`,
      { tags: { name: 'UserTimeline' } }
    );
    
    userTimelineDuration.add(res.timings.duration);
    
    const success = check(res, {
      'user timeline status is 200': (r) => r.status === 200,
      'user timeline response time < 500ms': (r) => r.timings.duration < 500,
    });
    
    if (success) successfulRequests.add(1);
    errorRate.add(!success);
  }
  
  else if (scenario < 0.80) {
    // ========== COMPOSE POST (15%) ==========
    const postText = randomString(100);
    
    const res = http.post(
      `${BASE_URL}/wrk2-api/post/compose`,
      `user_id=${userId}&username=user_${userId}&text=${encodeURIComponent(postText)}&media_ids=[]&media_types=[]&post_type=0`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        tags: { name: 'ComposePost' },
      }
    );
    
    composePostDuration.add(res.timings.duration);
    
    const success = check(res, {
      'compose post status is 200': (r) => r.status === 200,
      'compose post success': (r) => r.body && r.body.includes('Successfully'),
      'compose post response time < 1000ms': (r) => r.timings.duration < 1000,
    });
    
    if (success) successfulRequests.add(1);
    errorRate.add(!success);
  }
  
  else if (scenario < 0.90) {
    // ========== FOLLOW USER (10%) ==========
    const followeeId = randomUserId();
    
    const res = http.post(
      `${BASE_URL}/wrk2-api/user/follow`,
      `user_id=${userId}&followee_id=${followeeId}`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        tags: { name: 'FollowUser' },
      }
    );
    
    followDuration.add(res.timings.duration);
    
    const success = check(res, {
      'follow status is 200': (r) => r.status === 200,
      'follow success': (r) => r.body && r.body.includes('Success'),
    });
    
    if (success) successfulRequests.add(1);
    errorRate.add(!success);
  }
  
  else if (scenario < 0.95) {
    // ========== UNFOLLOW USER (5%) ==========
    const followeeId = randomUserId();
    
    const res = http.post(
      `${BASE_URL}/wrk2-api/user/unfollow`,
      `user_id=${userId}&followee_id=${followeeId}`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        tags: { name: 'UnfollowUser' },
      }
    );
    
    const success = check(res, {
      'unfollow status is 200': (r) => r.status === 200,
      'unfollow success': (r) => r.body && r.body.includes('Success'),
    });
    
    if (success) successfulRequests.add(1);
    errorRate.add(!success);
  }
  
  else {
    // ========== REGISTER USER (5%) ==========
    const newUserId = Math.floor(Math.random() * 100000) + 10000;
    const username = `testuser_${newUserId}`;
    
    const res = http.post(
      `${BASE_URL}/wrk2-api/user/register`,
      `first_name=Test&last_name=User&username=${username}&password=testpass&user_id=${newUserId}`,
      {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        tags: { name: 'RegisterUser' },
      }
    );
    
    const success = check(res, {
      'register status is 200': (r) => r.status === 200,
      'register success': (r) => r.body && r.body.includes('Success'),
    });
    
    if (success) successfulRequests.add(1);
    errorRate.add(!success);
  }
  
  // Think time between requests (simulates real user behavior)
  sleep(Math.random() * 2 + 1); // 1-3 seconds
}

export function handleSummary(data) {
  const { metrics } = data;
  
  return {
    'stdout': `
================================================================================
                        LOAD TEST SUMMARY
================================================================================

📊 OVERALL RESULTS

Total Requests:      ${metrics.http_reqs?.values?.count || 0}
Successful:          ${metrics.successful_requests?.values?.count || 0}
Failed:              ${Math.round((metrics.errors?.values?.rate || 0) * (metrics.http_reqs?.values?.count || 0))}
Error Rate:          ${((metrics.errors?.values?.rate || 0) * 100).toFixed(2)}%

⏱️  RESPONSE TIMES

  Overall:
    - Average:       ${(metrics.http_req_duration?.values?.avg || 0).toFixed(2)} ms
    - Median (p50):  ${(metrics.http_req_duration?.values?.med || 0).toFixed(2)} ms
    - p95:           ${(metrics.http_req_duration?.values['p(95)'] || 0).toFixed(2)} ms
    - p99:           ${(metrics.http_req_duration?.values['p(99)'] || 0).toFixed(2)} ms
    - Max:           ${(metrics.http_req_duration?.values?.max || 0).toFixed(2)} ms

  By Endpoint:
    - Home Timeline: ${(metrics.home_timeline_duration?.values?.avg || 0).toFixed(2)} ms avg
    - User Timeline: ${(metrics.user_timeline_duration?.values?.avg || 0).toFixed(2)} ms avg
    - Compose Post:  ${(metrics.compose_post_duration?.values?.avg || 0).toFixed(2)} ms avg
    - Follow:        ${(metrics.follow_duration?.values?.avg || 0).toFixed(2)} ms avg

🚀 THROUGHPUT

  Requests/sec:      ${(metrics.http_reqs?.values?.rate || 0).toFixed(2)}
  Data received:     ${((metrics.data_received?.values?.count || 0) / 1024 / 1024).toFixed(2)} MB
  Data sent:         ${((metrics.data_sent?.values?.count || 0) / 1024 / 1024).toFixed(2)} MB

👥 VIRTUAL USERS

  Max VUs:           ${metrics.vus?.values?.max || 0}
  Test Duration:     ${(data.state?.testRunDurationMs / 1000 / 60).toFixed(2)} minutes

================================================================================
`,
    'load-test-results.json': JSON.stringify(data, null, 2),
  };
}
