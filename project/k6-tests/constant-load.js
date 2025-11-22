// k6 Constant Load Test Script
//
// WHAT THIS DOES:
// This script simulates a constant, steady load on the system. It maintains a fixed
// number of virtual users (VUs) for a specified duration. This test helps establish
// baseline performance metrics.
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
import { Rate, Trend } from 'k6/metrics';

// Custom metrics - track specific aspects of performance
// These are in addition to k6's built-in metrics
const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');

// Test configuration
export const options = {
  // Number of virtual users to maintain
  // Each VU simulates one user making requests
  vus: 100,  // Start with 100 concurrent users
  
  // Test duration
  // Format: '30s' = 30 seconds, '5m' = 5 minutes, '1h' = 1 hour
  duration: '10m',  // Run for 10 minutes
  
  // Thresholds - test fails if these are not met
  // This helps catch performance regressions
  thresholds: {
    // 95% of requests should complete in under 500ms
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    
    // Error rate should be less than 1%
    'http_req_failed': ['rate<0.01'],
    
    // At least 100 requests per second
    'http_reqs': ['rate>100'],
  },
};

// Base URL of the application
// In Kubernetes, this would be the LoadBalancer or NodePort URL
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Test data - you can parameterize this
const testUsers = [
  { id: 1, username: 'user1' },
  { id: 2, username: 'user2' },
  { id: 3, username: 'user3' },
];

// Main test function
// This function runs for each virtual user, repeatedly, for the test duration
export default function () {
  // Simulate a user browsing the social network
  
  // 1. Get user profile (most common operation)
  const userProfileResponse = http.get(`${BASE_URL}/user/${testUsers[0].id}`);
  
  // Check if the request was successful
  const profileSuccess = check(userProfileResponse, {
    'user profile status is 200': (r) => r.status === 200,
    'user profile response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  // Track custom metrics
  errorRate.add(!profileSuccess);
  responseTime.add(userProfileResponse.timings.duration);
  
  // Think time - simulate user reading the page
  // Real users don't click instantly, they read and think
  sleep(1);  // Wait 1 second
  
  // 2. Get user's social graph (friends list)
  const socialGraphResponse = http.get(`${BASE_URL}/social-graph/${testUsers[0].id}/followers`);
  
  check(socialGraphResponse, {
    'social graph status is 200': (r) => r.status === 200,
    'social graph response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  sleep(1);
  
  // 3. Get user timeline
  const timelineResponse = http.get(`${BASE_URL}/user-timeline/${testUsers[0].id}`);
  
  check(timelineResponse, {
    'timeline status is 200': (r) => r.status === 200,
    'timeline response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  // Think time before next iteration
  sleep(2);
}

// Setup function - runs once before the test starts
// Use this to prepare test data, authenticate, etc.
export function setup() {
  console.log('Setting up constant load test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log(`Virtual Users: ${options.vus}`);
  console.log(`Duration: ${options.duration}`);
  
  // You could authenticate here and return a token
  // return { authToken: '...' };
  
  return {};
}

// Teardown function - runs once after the test completes
// Use this to clean up test data, generate reports, etc.
export function teardown(data) {
  console.log('Constant load test completed!');
  console.log('Check the summary for detailed metrics.');
}

