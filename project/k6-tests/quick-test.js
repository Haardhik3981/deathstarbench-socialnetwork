// k6 Quick Test - 20 Second Validation Test
//
// WHAT THIS DOES:
// This is a shortened version of the constant-load test that runs for only 20 seconds.
// Use this to quickly validate that metrics collection, extraction, and recording are
// working correctly before running longer tests.
//
// KEY FEATURES:
// - Same structure as constant-load test (uses wrk2-api endpoints)
// - Only 20 seconds duration
// - Low user count (10 VUs) for quick execution
// - Includes all key metrics (p50, p95, p99, throughput, success rate)
//
// USAGE:
//   ./scripts/run-test-with-metrics.sh quick-test
//   BASE_URL=http://your-url:8080 ./scripts/run-test-with-metrics.sh quick-test

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';
import {
  encodeFormData,
  generateRandomUser,
  generateRandomPost,
  registerUser,
  ensureUserHasFollower,
  setupSeedUser,
} from './test-helpers.js';

// Custom metrics - same as constant-load
const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');

// Test configuration - Quick 20 second test
export const options = {
  // Low user count for quick execution
  vus: 10,  // 10 concurrent users
  
  // Very short duration - just 20 seconds
  duration: '20s',
  
  // Thresholds - same as constant-load
  // Including p50, p95, p99 ensures these percentiles are calculated
  thresholds: {
    'http_req_duration': [
      'p(50)<500',   // 50% of requests should be under 500ms
      'p(95)<1000',  // 95% of requests should be under 1s
      'p(99)<2000',  // 99% of requests should be under 2s
    ],
    'http_req_failed': ['rate<0.05'],  // Less than 5% errors
    'http_reqs': ['rate>1'],  // At least 1 request per second
  },
};

// Base URL of the application
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Main test function - simplified version of constant-load
export default function (data) {
  // Simulate a user's workflow on the social network (same as constant-load but shorter)
  
  // 1. Register a new user (POST /wrk2-api/user/register)
  const newUser = generateRandomUser();
  const registerResponse = registerUser(BASE_URL, newUser);
  
  const registerSuccess = check(registerResponse, {
    'register status is 200': (r) => r.status === 200,
    'register response time < 2000ms': (r) => r.timings.duration < 2000,
  });
  
  errorRate.add(!registerSuccess);
  responseTime.add(registerResponse.timings.duration);
  
  // Only continue if registration succeeded
  if (!registerSuccess) {
    sleep(0.5);
    return;
  }
  
  // Shorter think time for quick test
  sleep(0.5);
  
  // 2. Create a follower relationship (simplified - use seed user)
  const seedUserId = (data && data.seedUserId) || 1;
  ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);
  sleep(0.3);
  
  // 3. Compose a post (POST /wrk2-api/post/compose)
  const postData = generateRandomPost(newUser.user_id, newUser.username);
  
  const composeResponse = http.post(
    `${BASE_URL}/wrk2-api/post/compose`,
    encodeFormData(postData),
    {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      tags: { name: 'ComposePost' }
    }
  );
  
  const composeSuccess = check(composeResponse, {
    'compose status is 200': (r) => r.status === 200,
    'compose response time < 2000ms': (r) => r.timings.duration < 2000,
  });
  
  errorRate.add(!composeSuccess);
  responseTime.add(composeResponse.timings.duration);
  
  sleep(0.5);
  
  // 4. Read home timeline (GET /wrk2-api/home-timeline/read)
  const timelineResponse = http.get(
    `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${newUser.user_id}&start=0&stop=10`,
    { tags: { name: 'ReadHomeTimeline' } }
  );
  
  check(timelineResponse, {
    'timeline status is 200': (r) => r.status === 200,
    'timeline response time < 2000ms': (r) => r.timings.duration < 2000,
  });
  
  // Shorter think time before next iteration
  sleep(0.5);
}

// Setup function - same as constant-load
export function setup() {
  console.log('Setting up quick validation test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log(`Virtual Users: ${options.vus}`);
  console.log(`Duration: ${options.duration}`);
  console.log('This is a quick test to validate metrics collection.');
  
  // Create a seed user (user_id 1) that other users can follow
  return setupSeedUser(BASE_URL);
}

// Teardown function
export function teardown(data) {
  console.log('Quick test completed!');
  console.log('Check the metrics CSV file to verify all values are being recorded correctly.');
}

