// k6 Stress Test Script
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
import {
  encodeFormData,
  generateRandomUser,
  generateRandomPost,
  registerUser,
  ensureUserHasFollower,
  setupSeedUser,
} from './test-helpers.js';

const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');
const status200 = new Counter('status_200');
const status400 = new Counter('status_400');
const status500 = new Counter('status_500');
const statusOther = new Counter('status_other');

// Test configuration with gradual ramp-up
// Adjusted based on sweet-test results: peak at 400 VUs (slightly above sweet-test's 350)
export const options = {
  stages: [
    // Stage 1: Start with low load
    // 10 users for 2 minutes - establish baseline
    { duration: '2m', target: 10 },
    
    // Stage 2: Gradual increase
    // Increase gradually to allow autoscaling to respond
    // Based on sweet-test: system handles 350 VUs well, so we push slightly higher
    { duration: '2m', target: 50 },
    { duration: '2m', target: 100 },
    { duration: '2m', target: 150 },
    { duration: '2m', target: 200 },
    { duration: '2m', target: 250 },
    { duration: '2m', target: 300 },
    { duration: '2m', target: 350 },  // Sweet-test peak
    { duration: '2m', target: 400 },    // Slightly above sweet-test to find limits
    
    // Stage 3: Maintain peak to observe stability and find breaking point
    { duration: '5m', target: 400 },
    
    // Stage 4: Gradual ramp-down
    { duration: '2m', target: 300 },
    { duration: '2m', target: 200 },
    { duration: '2m', target: 100 },
    { duration: '2m', target: 50 },
    { duration: '1m', target: 0 },
  ],
  
  thresholds: {
    // Adjusted thresholds based on sweet-test performance
    // Sweet-test achieved: p50=83ms, p95=10s, 18.64% errors at 350 VUs
    'http_req_duration': [
      'p(50)<800',   // 50% of requests should be under 800ms (allows some degradation)
      'p(95)<2000',  // 95% of requests should be under 2s
      'p(99)<5000',  // 99% of requests should be under 5s (allows higher latency during stress)
    ],
    'http_req_failed': ['rate<0.20'],  // Allow up to 20% errors at peak (stress test)
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function (data) {
  // Mix of different operations using wrk2-api endpoints
  // Operations are weighted: 70% reads, 30% writes
  const isWrite = Math.random() < 0.3;
  
  let response;
  let success = false;
  
  if (isWrite) {
    // Write operations: Register user, follow, compose post
    const operation = Math.random();
    
    if (operation < 0.4) {
      // 40% of writes: Register new user
      const newUser = generateRandomUser();
      response = registerUser(BASE_URL, newUser);
      
      // Track status codes
      if (response.status === 200) {
        status200.add(1);
      } else if (response.status === 400) {
        status400.add(1);
      } else if (response.status >= 500) {
        status500.add(1);
      } else {
        statusOther.add(1);
      }
      
      success = check(response, {
        'register status is 200': (r) => r.status === 200,
        'register response time < 2000ms': (r) => r.timings.duration < 2000,
      });
    } else if (operation < 0.7) {
      // 30% of writes: Compose post (need to register user first)
      const newUser = generateRandomUser();
      const registerResponse = registerUser(BASE_URL, newUser);
      
      if (registerResponse.status === 200) {
        // Create follower relationship before composing
        const seedUserId = (data && data.seedUserId) || 1;
        ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);
        
        // Compose post
        const postData = generateRandomPost(newUser.user_id, newUser.username);
        response = http.post(
          `${BASE_URL}/wrk2-api/post/compose`,
          encodeFormData(postData),
          {
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            tags: { name: 'ComposePost' }
          }
        );
        
        // Track status codes
        if (response.status === 200) {
          status200.add(1);
        } else if (response.status === 400) {
          status400.add(1);
        } else if (response.status >= 500) {
          status500.add(1);
        } else {
          statusOther.add(1);
        }
        
        success = check(response, {
          'compose status is 200': (r) => r.status === 200,
          'compose response time < 2000ms': (r) => r.timings.duration < 2000,
        });
      } else {
        // Registration failed, skip compose
        response = registerResponse;
        success = false;
      }
    } else {
      // 30% of writes: Follow operation (use seed user)
      const newUser = generateRandomUser();
      const registerResponse = registerUser(BASE_URL, newUser);
      
      if (registerResponse.status === 200) {
        const seedUserId = (data && data.seedUserId) || 1;
        response = ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);
        
        // Track status codes
        if (response.status === 200) {
          status200.add(1);
        } else if (response.status >= 500) {
          status500.add(1);
        } else {
          statusOther.add(1);
        }
        
        success = check(response, {
          'follow status is 200': (r) => r.status === 200,
        });
      } else {
        response = registerResponse;
        success = false;
      }
    }
  } else {
    // Read operations: Read home timeline or user timeline
    // Use a random user_id (1-1000) for reads
    const userId = Math.floor(Math.random() * 1000) + 1;
    
    if (Math.random() < 0.5) {
      // 50% of reads: Home timeline
      response = http.get(
        `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${userId}&start=0&stop=10`,
        { tags: { name: 'ReadHomeTimeline' } }
      );
    } else {
      // 50% of reads: User timeline
      response = http.get(
        `${BASE_URL}/wrk2-api/user-timeline/read?user_id=${userId}&start=0&stop=10`,
        { tags: { name: 'ReadUserTimeline' } }
      );
    }
    
    // Track status codes
    if (response.status === 200) {
      status200.add(1);
    } else if (response.status >= 500) {
      status500.add(1);
    } else {
      statusOther.add(1);
    }
    
    success = check(response, {
      'timeline status is 200': (r) => r.status === 200,
      'timeline response time < 2000ms': (r) => r.timings.duration < 2000,
    });
  }
  
  // Track metrics
  if (response) {
    errorRate.add(!success);
    responseTime.add(response.timings.duration);
  }
  
  // Think time - users don't click instantly
  // As system gets slower, users might wait longer (simulated by random sleep)
  sleep(Math.random() * 3 + 1);  // Sleep 1-4 seconds
}

export function setup() {
  console.log('Setting up stress test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('This test will gradually increase load to find breaking points.');
  console.log('Creating seed user (user_id 1) for follower relationships...');
  
  // Create seed user for follower relationships
  return setupSeedUser(BASE_URL);
}

export function teardown(data) {
  console.log('Stress test completed!');
  console.log('Analyze the results to identify:');
  console.log('- Maximum sustainable throughput');
  console.log('- Latency degradation patterns');
  console.log('- Autoscaling behavior');
  console.log('- Resource bottlenecks');
  console.log('\nStatus Code Summary:');
  
  // Try to read status counters
  let status200Count = 0;
  let status400Count = 0;
  let status500Count = 0;
  let statusOtherCount = 0;
  
  try {
    if (status200.values) {
      if (typeof status200.values.get === 'function') {
        status200Count = status200.values.get('') || 0;
      } else if (status200.values['']) {
        status200Count = status200.values[''];
      }
    }
    if (status400.values) {
      if (typeof status400.values.get === 'function') {
        status400Count = status400.values.get('') || 0;
      } else if (status400.values['']) {
        status400Count = status400.values[''];
      }
    }
    if (status500.values) {
      if (typeof status500.values.get === 'function') {
        status500Count = status500.values.get('') || 0;
      } else if (status500.values['']) {
        status500Count = status500.values[''];
      }
    }
    if (statusOther.values) {
      if (typeof statusOther.values.get === 'function') {
        statusOtherCount = statusOther.values.get('') || 0;
      } else if (statusOther.values['']) {
        statusOtherCount = statusOther.values[''];
      }
    }
  } catch (e) {
    // Ignore errors
  }
  
  console.log(`  200 OK: ${status200Count}`);
  console.log(`  400 Bad Request: ${status400Count}`);
  console.log(`  500+ Server Error: ${status500Count}`);
  console.log(`  Other: ${statusOtherCount}`);
}

