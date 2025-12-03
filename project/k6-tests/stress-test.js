// k6 Stress Test Script
//
// NOTE: This test uses different endpoints (/user-timeline/1/posts) that may not
// trigger the compose-post flow. If you want to test compose-post specifically,
// use constant-load.js which uses the wrk2-api endpoints and includes the
// follower relationship fix to avoid "ZADD: no key specified" errors.
//
// WHAT THIS DOES:
// This script gradually increases load until the system reaches its breaking point.
// Unlike the peak test (sudden spike), this test ramps up slowly, allowing you to
// observe how the system scales and where bottlenecks occur.
//
// KEY CONCEPTS:
// - Gradual ramp-up: Slowly increasing load
// - Breaking point: The load level where the system starts to fail
// - Saturation: The point where adding more load doesn't increase throughput
// - Bottleneck identification: Which resource (CPU, memory, database) fails first
//
// WHY WE USE IT:
// Stress testing helps us understand:
// - Maximum sustainable throughput
// - How autoscaling behaves under gradual load increase
// - Resource bottlenecks (CPU, memory, database connections)
// - Latency degradation as load increases
// - The relationship between load and performance

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');
const requestCount = new Counter('total_requests');

// Test configuration with gradual ramp-up
export const options = {
  stages: [
    // Stage 1: Start with low load
    // 10 users for 2 minutes - establish baseline
    { duration: '2m', target: 10 },
    
    // Stage 2: Gradual increase
    // Increase by 50 users every 2 minutes
    // This gives the system time to scale and stabilize
    { duration: '2m', target: 50 },
    { duration: '2m', target: 100 },
    { duration: '2m', target: 150 },
    { duration: '2m', target: 200 },
    { duration: '2m', target: 250 },
    { duration: '2m', target: 300 },
    { duration: '2m', target: 400 },
    { duration: '2m', target: 500 },
    
    // Stage 3: Continue increasing to find breaking point
    { duration: '2m', target: 600 },
    { duration: '2m', target: 700 },
    { duration: '2m', target: 800 },
    { duration: '2m', target: 900 },
    { duration: '2m', target: 1000 },
    
    // Stage 4: Maintain peak to observe stability
    { duration: '5m', target: 1000 },
    
    // Stage 5: Gradual ramp-down
    { duration: '2m', target: 500 },
    { duration: '2m', target: 250 },
    { duration: '2m', target: 100 },
    { duration: '2m', target: 50 },
    { duration: '1m', target: 0 },
  ],
  
  thresholds: {
    // Track metrics at different percentiles
    // As load increases, we expect latency to increase
    'http_req_duration': [
      'p(50)<500',   // 50% of requests should be under 500ms
      'p(95)<2000',  // 95% of requests should be under 2s
      'p(99)<5000',  // 99% of requests should be under 5s
    ],
    'http_req_failed': ['rate<0.1'],  // Allow up to 10% errors at peak
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  // Mix of different operations to simulate realistic load
  const operations = [
    'getUserProfile',
    'getSocialGraph',
    'getTimeline',
    'createPost',
    'updateProfile',
  ];
  
  // Randomly select an operation
  // This simulates real user behavior
  const operation = operations[Math.floor(Math.random() * operations.length)];
  
  let response;
  let success = false;
  
  switch (operation) {
    case 'getUserProfile':
      response = http.get(`${BASE_URL}/user/1`, {
        tags: { name: 'GetUserProfile' },
      });
      success = check(response, {
        'status is 200': (r) => r.status === 200,
      });
      break;
      
    case 'getSocialGraph':
      response = http.get(`${BASE_URL}/social-graph/1/followers`, {
        tags: { name: 'GetSocialGraph' },
      });
      success = check(response, {
        'status is 200': (r) => r.status === 200,
      });
      break;
      
    case 'getTimeline':
      response = http.get(`${BASE_URL}/user-timeline/1`, {
        tags: { name: 'GetTimeline' },
      });
      success = check(response, {
        'status is 200': (r) => r.status === 200,
      });
      break;
      
    case 'createPost':
      response = http.post(
        `${BASE_URL}/user-timeline/1/posts`,
        JSON.stringify({
          content: `Stress test post at ${Date.now()}`,
          timestamp: Date.now(),
        }),
        {
          headers: { 'Content-Type': 'application/json' },
          tags: { name: 'CreatePost' },
        }
      );
      success = check(response, {
        'status is 200 or 201': (r) => r.status === 200 || r.status === 201,
      });
      break;
      
    case 'updateProfile':
      response = http.put(
        `${BASE_URL}/user/1`,
        JSON.stringify({
          bio: `Updated at ${Date.now()}`,
        }),
        {
          headers: { 'Content-Type': 'application/json' },
          tags: { name: 'UpdateProfile' },
        }
      );
      success = check(response, {
        'status is 200': (r) => r.status === 200,
      });
      break;
  }
  
  // Track metrics
  if (response) {
    errorRate.add(!success);
    responseTime.add(response.timings.duration);
    requestCount.add(1);
  }
  
  // Think time - users don't click instantly
  // As system gets slower, users might wait longer (simulated by random sleep)
  sleep(Math.random() * 3 + 1);  // Sleep 1-4 seconds
}

export function setup() {
  console.log('Setting up stress test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('This test will gradually increase load to find breaking points.');
  return {};
}

export function teardown(data) {
  console.log('Stress test completed!');
  console.log('Analyze the results to identify:');
  console.log('- Maximum sustainable throughput');
  console.log('- Latency degradation patterns');
  console.log('- Autoscaling behavior');
  console.log('- Resource bottlenecks');
}

