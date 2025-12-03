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
    { duration: '5m', target: 50 },   // Stay at 50 users for 5 minutes
    { duration: '1m', target: 0 },    // Ramp down to 0 over 1 minute
  ],
  
  // Thresholds - test fails if these are not met
  thresholds: {
    // 95% of requests should complete in under 1000ms
    'http_req_duration': ['p(95)<1000', 'p(99)<2000'],
    
    // Error rate should be less than 5% (allow some errors during load)
    'http_req_failed': ['rate<0.05'],
    
    // At least 10 requests per second
    'http_reqs': ['rate>10'],
  },
};

// Base URL of the application
// In Kubernetes, this would be the LoadBalancer or NodePort URL
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Helper function to generate random user data
function generateRandomUser() {
  const id = Math.floor(Math.random() * 1000000);
  const username = `user_${id}_${Date.now()}`;
  return {
    user_id: id,
    username: username,
    first_name: `FirstName${id}`,
    last_name: `LastName${id}`,
    password: `password${id}`,
  };
}

// Helper function to generate random post data
function generateRandomPost(userId, username) {
  const postTypes = [0, 1, 2]; // Different post types
  return {
    user_id: userId,
    username: username,
    post_type: postTypes[Math.floor(Math.random() * postTypes.length)],
    text: `This is a test post from user ${username} at ${new Date().toISOString()}`,
    media_ids: JSON.stringify([]),
    media_types: JSON.stringify([]),
  };
}

// Helper function to encode form data
function encodeFormData(data) {
  return Object.keys(data)
    .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(data[key])}`)
    .join('&');
}

// Main test function
// This function runs for each virtual user, repeatedly, for the test duration
export default function () {
  // Simulate a user's workflow on the social network
  
  // 1. Register a new user (POST /wrk2-api/user/register)
  // NOTE: The endpoint expects form-encoded data, not JSON!
  const newUser = generateRandomUser();
  const registerPayload = {
    user_id: newUser.user_id.toString(),
    username: newUser.username,
    first_name: newUser.first_name,
    last_name: newUser.last_name,
    password: newUser.password,
  };
  
  // Send as form-encoded data (application/x-www-form-urlencoded)
  const registerResponse = http.post(
    `${BASE_URL}/wrk2-api/user/register`,
    encodeFormData(registerPayload),
    {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      tags: { name: 'RegisterUser' }
    }
  );
  
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
  
  return {};
}

// Teardown function - runs once after the test completes
export function teardown(data) {
  console.log('Constant load test completed!');
  console.log('Check the summary for detailed metrics.');
  console.log('\nStatus Code Summary:');
  console.log(`  200 OK: ${status200.values[''] || 0}`);
  console.log(`  400 Bad Request: ${status400.values[''] || 0}`);
  console.log(`  500+ Server Error: ${status500.values[''] || 0}`);
  console.log(`  Other: ${statusOther.values[''] || 0}`);
}
