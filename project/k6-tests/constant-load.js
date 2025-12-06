// k6 Constant Load Test Script for DeathStarBench Social Network
//
// WHAT THIS DOES:
// This script simulates a constant, steady load on the DeathStarBench social network.
// It uses the wrk2-api endpoints which don't require authentication cookies,
// making them ideal for load testing.
//
// KEY CONCEPTS:
// - Virtual Users (VUs): Simulated users making requests
// - Duration: How long the test runs
// - Ramping: Gradually increasing/decreasing VUs (not used in constant load)
// - Metrics: k6 automatically collects metrics like response time, throughput, errors
//
// WHY WE USE IT:
// Constant load testing helps us understand:
// - Baseline performance (average latency, throughput)
// - System stability under steady load
// - Resource consumption patterns
// - Whether the system can handle expected production traffic

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import {
  encodeFormData,
  generateRandomUser,
  generateRandomPost,
  registerUser,
  ensureUserHasFollower,
  setupSeedUser,
} from './test-helpers.js';

// Custom metrics - track specific aspects of performance
const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');
const status200 = new Counter('status_200');
const status400 = new Counter('status_400');
const status500 = new Counter('status_500');
const statusOther = new Counter('status_other');

// Test configuration
export const options = {
  // Number of virtual users to maintain
  // Each VU simulates one user making requests
  stages: [
    { duration: '1m', target: 50 },   // Ramp up to 50 users over 1 minute
    { duration: '1m', target: 50 },   // Stay at 50 users for 5 minutes
    { duration: '1m', target: 0 },    // Ramp down to 0 over 1 minute
  ],
  
  // Thresholds - test fails if these are not met
  // Including p50, p95, and p99 ensures these percentiles are calculated and included in summary
  thresholds: {
    // Latency thresholds - ensures p50, p95, p99 are calculated
    'http_req_duration': [
      'p(50)<500',   // 50% of requests should be under 500ms (target for your experiments)
      'p(95)<1000',  // 95% of requests should be under 1s
      'p(99)<2000',  // 99% of requests should be under 2s
    ],
    
    // Error rate should be less than 5% (allow some errors during load)
    'http_req_failed': ['rate<0.05'],
    
    // At least 10 requests per second
    'http_reqs': ['rate>10'],
  },
};

// Base URL of the application
// In Kubernetes, this would be the LoadBalancer or NodePort URL
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Helper functions are now imported from test-helpers.js

// Main test function
// This function runs for each virtual user, repeatedly, for the test duration
export default function (data) {
  // Simulate a user's workflow on the social network
  
  // 1. Register a new user (POST /wrk2-api/user/register)
  // NOTE: The endpoint expects form-encoded data, not JSON!
  const newUser = generateRandomUser();
  const registerResponse = registerUser(BASE_URL, newUser);
  
  // Track status codes
  if (registerResponse.status === 200) {
    status200.add(1);
  } else if (registerResponse.status === 400) {
    status400.add(1);
  } else if (registerResponse.status >= 500) {
    status500.add(1);
  } else {
    statusOther.add(1);
  }
  
  const registerSuccess = check(registerResponse, {
    'register status is 200': (r) => r.status === 200,
    'register response time < 2000ms': (r) => r.timings.duration < 2000,
  });
  
  // Log error details for debugging (log more frequently to understand the issue)
  if (registerResponse.status !== 200 && Math.random() < 0.05) { // Log ~5% of non-200 responses
    const bodyPreview = registerResponse.body ? registerResponse.body.substring(0, 200) : '(no body)';
    console.log(`[VU ${__VU}] Register: status=${registerResponse.status}, body="${bodyPreview}"`);
  }
  
  errorRate.add(!registerSuccess);
  responseTime.add(registerResponse.timings.duration);
  
  // Only continue if registration succeeded
  if (!registerSuccess) {
    sleep(1);
    return;
  }
  
  // Think time - simulate user reading the page
  sleep(1);
  
  // 1.5. Create a follower relationship BEFORE composing posts
  // This avoids the "ZADD: no key specified" error when users have no followers
  // Strategy: Use a seed user (user_id 1) that should exist from setup
  // Have the seed user follow the new user, so new user has at least one follower
  const seedUserId = (data && data.seedUserId) || 1; // Fallback to 1 if setup data missing
  const followResponse = ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);
  
  // Track follow status (non-blocking - if seed user doesn't exist, we'll still try compose)
  if (followResponse.status === 200) {
    status200.add(1);
  } else if (followResponse.status >= 500) {
    status500.add(1);
  }
  
  // Small sleep after follow operation
  sleep(0.5);
  
  // 2. Compose a post (POST /wrk2-api/post/compose)
  // NOTE: Also expects form-encoded data
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
  
  // Track compose status codes
  if (composeResponse.status === 200) {
    status200.add(1);
  } else if (composeResponse.status === 400) {
    status400.add(1);
  } else if (composeResponse.status >= 500) {
    status500.add(1);
  } else {
    statusOther.add(1);
  }
  
  if (!composeSuccess && Math.random() < 0.01) {
    console.log(`Compose failed: status=${composeResponse.status}, body=${composeResponse.body.substring(0, 200)}`);
  }
  
  errorRate.add(!composeSuccess);
  responseTime.add(composeResponse.timings.duration);
  
  sleep(1);
  
  // 3. Read home timeline (GET /wrk2-api/home-timeline/read?user_id=X&start=0&stop=10)
  const timelineResponse = http.get(
    `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${newUser.user_id}&start=0&stop=10`,
    { tags: { name: 'ReadHomeTimeline' } }
  );
  
  check(timelineResponse, {
    'timeline status is 200': (r) => r.status === 200,
    'timeline response time < 2000ms': (r) => r.timings.duration < 2000,
  });
  
  // Think time before next iteration
  sleep(2);
}

// Setup function - runs once before the test starts
export function setup() {
  console.log('Setting up constant load test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log(`Test stages: ${JSON.stringify(options.stages)}`);
  
  // Create a seed user (user_id 1) that other users can follow
  // This ensures users have at least one follower before composing posts
  // This avoids the "ZADD: no key specified" error
  return setupSeedUser(BASE_URL);
}

// Teardown function - runs once after the test completes
export function teardown(data) {
  console.log('Constant load test completed!');
  console.log('Check the summary for detailed metrics.');
  console.log('\nStatus Code Summary:');
  
  // k6 Counter metrics store values in a Map-like structure
  // The key is usually an empty string for untagged metrics
  let status200Count = 0;
  let status400Count = 0;
  let status500Count = 0;
  let statusOtherCount = 0;
  
  // Try to get values from the Counter metrics
  try {
    // Counter.values is a Map, get the value for the default tag (empty string)
    if (status200.values && status200.values.get) {
      status200Count = status200.values.get('') || 0;
    } else if (status200.values && status200.values['']) {
      status200Count = status200.values[''] || 0;
    }
    
    if (status400.values && status400.values.get) {
      status400Count = status400.values.get('') || 0;
    } else if (status400.values && status400.values['']) {
      status400Count = status400.values[''] || 0;
    }
    
    if (status500.values && status500.values.get) {
      status500Count = status500.values.get('') || 0;
    } else if (status500.values && status500.values['']) {
      status500Count = status500.values[''] || 0;
    }
    
    if (statusOther.values && statusOther.values.get) {
      statusOtherCount = statusOther.values.get('') || 0;
    } else if (statusOther.values && statusOther.values['']) {
      statusOtherCount = statusOther.values[''] || 0;
    }
  } catch (e) {
    // If we can't read the values, just show 0
    console.log('  (Unable to read status code counters)');
  }
  
  console.log(`  200 OK: ${status200Count}`);
  console.log(`  400 Bad Request: ${status400Count}`);
  console.log(`  500+ Server Error: ${status500Count}`);
  console.log(`  Other: ${statusOtherCount}`);
  
  // Note: Counter.values may not be accessible in teardown
  // The actual counts are shown in the CUSTOM metrics section above
  if (status200Count === 0 && status400Count === 0 && status500Count === 0 && statusOtherCount === 0) {
    console.log('\nNote: Status counters show 0, but check the CUSTOM metrics section above');
    console.log('      for actual status_200 count (should match successful requests)');
  }
}
