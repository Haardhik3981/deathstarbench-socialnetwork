// k6 Endurance/Soak Test Script
//
// WHAT THIS DOES:
// This script runs a moderate, steady load for an extended period (hours). It's
// designed to identify issues that only appear over time, such as memory leaks,
// resource exhaustion, or gradual performance degradation.
//
// KEY CONCEPTS:
// - Long duration: Tests run for hours, not minutes
// - Moderate load: Not maximum load, but sustained over time
// - Memory leaks: Gradual increase in memory usage
// - Resource exhaustion: Running out of connections, file handles, etc.
// - Performance degradation: System getting slower over time
//
// WHY WE USE IT:
// Endurance testing helps us identify:
// - Memory leaks (memory usage gradually increasing)
// - Resource leaks (database connections, file handles)
// - Performance degradation over time
// - Autoscaler stability (does it keep scaling correctly?)
// - Cost analysis (how much does it cost to run for X hours?)

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');
const requestCount = new Counter('total_requests');
const activeUsers = new Gauge('active_users');

// Test configuration for long-duration test
export const options = {
  // Moderate, steady load for extended period
  stages: [
    // Ramp up to target load
    { duration: '10m', target: 100 },
    
    // Maintain steady load for 5 hours
    // This is the core of the endurance test
    { duration: '5h', target: 100 },
    
    // Ramp down
    { duration: '10m', target: 0 },
  ],
  
  thresholds: {
    // Stricter thresholds for endurance test
    // System should maintain performance over time
    'http_req_duration': [
      'p(95)<500',   // 95% of requests should be under 500ms
      'p(99)<1000',  // 99% of requests should be under 1s
    ],
    'http_req_failed': ['rate<0.01'],  // Less than 1% errors
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Track test start time to measure elapsed time
const testStartTime = Date.now();

export default function () {
  // Update active users gauge
  activeUsers.add(1);
  
  // Mix of operations similar to stress test
  // But with more realistic user behavior patterns
  const operations = [
    'getUserProfile',
    'getSocialGraph',
    'getTimeline',
    'browseTimeline',
    'createPost',
  ];
  
  const operation = operations[Math.floor(Math.random() * operations.length)];
  
  let response;
  let success = false;
  
  // Most operations are reads (realistic for social networks)
  const readWeight = 0.8;  // 80% reads, 20% writes
  const isRead = Math.random() < readWeight;
  
  if (isRead) {
    // Read operations
    switch (operation) {
      case 'getUserProfile':
        response = http.get(`${BASE_URL}/user/1`, {
          tags: { name: 'GetUserProfile' },
        });
        success = check(response, {
          'status is 200': (r) => r.status === 200,
          'response time < 500ms': (r) => r.timings.duration < 500,
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
      case 'browseTimeline':
        response = http.get(`${BASE_URL}/user-timeline/1`, {
          tags: { name: 'GetTimeline' },
        });
        success = check(response, {
          'status is 200': (r) => r.status === 200,
        });
        break;
    }
  } else {
    // Write operations (less frequent)
    if (operation === 'createPost') {
      response = http.post(
        `${BASE_URL}/user-timeline/1/posts`,
        JSON.stringify({
          content: `Endurance test post at ${Date.now()}`,
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
    }
  }
  
  // Track metrics
  if (response) {
    errorRate.add(!success);
    responseTime.add(response.timings.duration);
    requestCount.add(1);
    
    // Log if response time is unusually high (potential degradation)
    if (response.timings.duration > 2000) {
      console.log(`High response time detected: ${response.timings.duration}ms at ${Date.now() - testStartTime}ms into test`);
    }
  }
  
  // Realistic think time
  // Users spend time reading content
  sleep(Math.random() * 5 + 2);  // Sleep 2-7 seconds
}

export function setup() {
  console.log('Setting up endurance/soak test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('This test will run for 5+ hours to identify long-term issues.');
  console.log('Monitor for:');
  console.log('- Memory leaks (gradual memory increase)');
  console.log('- Performance degradation');
  console.log('- Resource exhaustion');
  return {
    startTime: Date.now(),
  };
}

export function teardown(data) {
  const duration = (Date.now() - data.startTime) / 1000 / 60;  // Duration in minutes
  console.log(`Endurance test completed after ${duration.toFixed(2)} minutes!`);
  console.log('Check the results for:');
  console.log('- Memory usage trends (should be stable)');
  console.log('- Response time trends (should not degrade)');
  console.log('- Error rates over time');
  console.log('- Pod count stability');
}

