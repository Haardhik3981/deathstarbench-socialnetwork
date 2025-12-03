// k6 Peak/Spike Test Script
//
// NOTE: This test uses different endpoints (/user-timeline/1/posts) that may not
// trigger the compose-post flow. If you want to test compose-post specifically,
// use constant-load.js which uses the wrk2-api endpoints and includes the
// follower relationship fix to avoid "ZADD: no key specified" errors.
//
// WHAT THIS DOES:
// This script simulates a sudden spike in traffic (e.g., a viral post, flash sale).
// It rapidly increases the number of virtual users, maintains peak load briefly,
// then returns to normal. This tests how the system handles sudden load increases.
//
// KEY CONCEPTS:
// - Ramping: Gradually or suddenly changing the number of VUs
// - Stages: Different phases of the test with different VU counts
// - Spike: Sudden increase in load
// - Recovery: How quickly the system recovers after the spike
//
// WHY WE USE IT:
// Peak testing helps us understand:
// - Maximum capacity of the system
// - How autoscaling responds to sudden load
// - Failure behavior under extreme load
// - Recovery time after load decreases

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

// Test configuration with stages
export const options = {
  // Stages define different phases of the test
  // Each stage has a target number of VUs and a duration
  stages: [
    // Stage 1: Normal load (baseline)
    // Start with 50 users for 2 minutes to establish baseline
    { duration: '2m', target: 50 },
    
    // Stage 2: Sudden spike
    // Rapidly ramp up to 1000 users in 30 seconds
    // This simulates a sudden traffic spike (e.g., viral post)
    { duration: '30s', target: 1000 },
    
    // Stage 3: Maintain peak load
    // Keep 1000 users for 1 minute to see how system handles sustained peak
    { duration: '1m', target: 1000 },
    
    // Stage 4: Sudden drop
    // Rapidly reduce to 100 users in 30 seconds
    // Tests recovery behavior
    { duration: '30s', target: 100 },
    
    // Stage 5: Return to normal
    // Gradually return to baseline
    { duration: '2m', target: 50 },
    
    // Stage 6: Cool down
    // Reduce to zero to end the test
    { duration: '1m', target: 0 },
  ],
  
  thresholds: {
    // More lenient thresholds for peak test
    // We expect some degradation during the spike
    'http_req_duration': ['p(95)<2000', 'p(99)<5000'],  // Allow higher latency during spike
    'http_req_failed': ['rate<0.05'],  // Allow up to 5% errors during spike
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Test function - simulates user behavior
export default function () {
  // During peak load, users might experience slower responses
  // We'll test multiple endpoints to see which ones fail first
  
  // 1. Try to get user profile
  const userProfileResponse = http.get(`${BASE_URL}/user/1`, {
    tags: { name: 'GetUserProfile' },
  });
  
  const profileSuccess = check(userProfileResponse, {
    'user profile status is 200': (r) => r.status === 200,
    'user profile response time < 2000ms': (r) => r.timings.duration < 2000,
  });
  
  errorRate.add(!profileSuccess);
  
  // Shorter think time during peak - users might be clicking faster
  // or the system might be slower, causing users to wait
  sleep(Math.random() * 2);  // Random sleep between 0-2 seconds
  
  // 2. Try to get social graph
  const socialGraphResponse = http.get(`${BASE_URL}/social-graph/1/followers`, {
    tags: { name: 'GetSocialGraph' },
  });
  
  check(socialGraphResponse, {
    'social graph status is 200': (r) => r.status === 200,
  });
  
  sleep(Math.random() * 2);
  
  // 3. Try to get timeline
  const timelineResponse = http.get(`${BASE_URL}/user-timeline/1`, {
    tags: { name: 'GetTimeline' },
  });
  
  check(timelineResponse, {
    'timeline status is 200': (r) => r.status === 200,
  });
  
  sleep(Math.random() * 2);
  
  // During peak, some users might try to create content
  // This is more resource-intensive
  if (Math.random() > 0.7) {  // 30% of requests
    const createPostResponse = http.post(
      `${BASE_URL}/user-timeline/1/posts`,
      JSON.stringify({
        content: 'Test post during peak load',
        timestamp: Date.now(),
      }),
      {
        headers: { 'Content-Type': 'application/json' },
        tags: { name: 'CreatePost' },
      }
    );
    
    check(createPostResponse, {
      'create post status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    });
  }
}

export function setup() {
  console.log('Setting up peak/spike test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('This test will simulate a sudden traffic spike.');
  return {};
}

export function teardown(data) {
  console.log('Peak test completed!');
  console.log('Analyze the results to see:');
  console.log('- When autoscaling triggered');
  console.log('- Which endpoints failed first');
  console.log('- Recovery time after spike');
}

