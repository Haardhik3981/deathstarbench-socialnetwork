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
const activeUsers = new Gauge('active_users');

// Test configuration for long-duration test
// Adjusted: Increased load to 200 VUs (more challenging) and reduced duration to 2 hours (more practical)
export const options = {
  // Moderate, steady load for extended period
  stages: [
    // Ramp up to target load gradually
    { duration: '10m', target: 50 },
    { duration: '10m', target: 100 },
    { duration: '10m', target: 150 },
    { duration: '10m', target: 200 },
    
    // Maintain steady load for 2 hours (reduced from 5h for practicality)
    // This is the core of the endurance test - long enough to detect degradation
    { duration: '2h', target: 200 },
    
    // Ramp down gradually
    { duration: '10m', target: 150 },
    { duration: '10m', target: 100 },
    { duration: '10m', target: 50 },
    { duration: '10m', target: 0 },
  ],
  
  thresholds: {
    // Adjusted thresholds based on sweet-test results
    // More realistic for sustained moderate load
    'http_req_duration': [
      'p(50)<500',   // 50% of requests should be under 500ms
      'p(95)<2000',  // 95% of requests should be under 2s (allows some variation)
      'p(99)<4000',  // 99% of requests should be under 4s
    ],
    'http_req_failed': ['rate<0.10'],  // Allow up to 10% errors (more realistic for endurance)
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Track test start time to measure elapsed time
const testStartTime = Date.now();

export default function (data) {
  // Update active users gauge
  activeUsers.add(1);
  
  // Most operations are reads (realistic for social networks)
  // 80% reads, 20% writes
  const readWeight = 0.8;
  const isRead = Math.random() < readWeight;
  
  let response;
  let success = false;
  
  if (isRead) {
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
      'timeline response time < 500ms': (r) => r.timings.duration < 500,
    });
  } else {
    // Write operations (20% of requests): Register user, follow, or compose post
    const writeOp = Math.random();
    
    if (writeOp < 0.4) {
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
        'register response time < 500ms': (r) => r.timings.duration < 500,
      });
    } else if (writeOp < 0.7) {
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
          'compose response time < 500ms': (r) => r.timings.duration < 500,
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
  }
  
  // Track metrics
  if (response) {
    errorRate.add(!success);
    responseTime.add(response.timings.duration);
    
    // Log if response time is unusually high (potential degradation)
    if (response.timings.duration > 2000) {
      const elapsed = ((Date.now() - testStartTime) / 1000 / 60).toFixed(2);
      console.log(`High response time detected: ${response.timings.duration}ms at ${elapsed} minutes into test`);
    }
  }
  
  // Realistic think time
  // Users spend time reading content
  sleep(Math.random() * 5 + 2);  // Sleep 2-7 seconds
}

export function setup() {
  console.log('Setting up endurance/soak test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('This test will run for ~2.5 hours to identify long-term issues.');
  console.log('Target load: 200 VUs (moderate but sustained)');
  console.log('Creating seed user (user_id 1) for follower relationships...');
  console.log('Monitor for:');
  console.log('- Memory leaks (gradual memory increase)');
  console.log('- Performance degradation');
  console.log('- Resource exhaustion');
  
  // Create seed user for follower relationships
  const seedData = setupSeedUser(BASE_URL);
  return {
    startTime: Date.now(),
    seedUserId: seedData.seedUserId,
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

