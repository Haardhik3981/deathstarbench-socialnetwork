// k6 CPU-Intensive Test Script
//
// WHAT THIS DOES:
// This script generates CPU-intensive workload by performing computationally
// expensive operations on the client side and sending larger payloads to
// force server-side CPU processing. This helps test CPU-based autoscaling.
//
// KEY CONCEPTS:
// - CPU-intensive operations: Client-side computation + large payloads
// - Forced CPU load: Multiple operations per request
// - Reduced think time: More requests per second
//
// WHY WE USE IT:
// To test CPU-based HPA autoscaling by:
// - Generating actual CPU load (not just I/O)
// - Forcing services to process computationally expensive operations
// - Creating conditions where CPU hits 70% before memory hits 80%

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
const status500 = new Counter('status_500');

function cpuIntensiveOperation(iterations = 1000) {
  let result = 0;
  for (let i = 0; i < iterations; i++) {
    result += Math.sqrt(i) * Math.sin(i) * Math.cos(i);
  }
  return result;
}

function generateLargePost(userId, username) {
  const basePost = generateRandomPost(userId, username);
  const largeText = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '.repeat(50);
  basePost.text = largeText + basePost.text;
  const mentions = Array.from({ length: 20 }, (_, i) => `@user${i} `).join('');
  basePost.text = mentions + basePost.text;
  return basePost;
}

export const options = {
  stages: [
    { duration: '1m', target: 10 },
    { duration: '2m', target: 50 },
    { duration: '2m', target: 500 },
    { duration: '3m', target: 1000 },
    { duration: '3m', target: 500 },
    { duration: '3m', target: 250 },
    { duration: '3m', target: 100 },
  ],

  thresholds: {
    'http_req_duration': [
      'p(50)<1000',
      'p(95)<3000',
      'p(99)<5000',
    ],
    'http_req_failed': ['rate<0.15'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function (data) {
  cpuIntensiveOperation(500);

  const isWrite = Math.random() < 0.5;
  let response;
  let success = false;

  if (isWrite) {
    const operation = Math.random();

    if (operation < 0.5) {
      const newUser = generateRandomUser();
      response = registerUser(BASE_URL, newUser);

      if (response.status === 200) {
        status200.add(1);
      } else if (response.status >= 500) {
        status500.add(1);
      }

      success = check(response, {
        'register status is 200': (r) => r.status === 200,
      });
    } else {
      const newUser = generateRandomUser();
      const registerResponse = registerUser(BASE_URL, newUser);

      if (registerResponse.status === 200) {
        const seedUserId = (data && data.seedUserId) || 1;
        ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);

        const postData = generateLargePost(newUser.user_id, newUser.username);
        response = http.post(
          `${BASE_URL}/wrk2-api/post/compose`,
          encodeFormData(postData),
          {
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            tags: { name: 'ComposePost' }
          }
        );

        if (response.status === 200) {
          status200.add(1);
        } else if (response.status >= 500) {
          status500.add(1);
        }

        success = check(response, {
          'compose status is 200': (r) => r.status === 200,
        });
      } else {
        response = registerResponse;
        success = false;
      }
    }
  } else {
    const userId = Math.floor(Math.random() * 1000) + 1;
    const numReads = 2;

    for (let i = 0; i < numReads; i++) {
      if (Math.random() < 0.5) {
        response = http.get(
          `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${userId}&start=0&stop=20`,
          { tags: { name: 'ReadHomeTimeline' } }
        );
      } else {
        response = http.get(
          `${BASE_URL}/wrk2-api/user-timeline/read?user_id=${userId}&start=0&stop=20`,
          { tags: { name: 'ReadUserTimeline' } }
        );
      }

      if (response.status === 200) {
        status200.add(1);
      } else if (response.status >= 500) {
        status500.add(1);
      }
    }

    success = check(response, {
      'timeline status is 200': (r) => r.status === 200,
    });
  }

  if (response) {
    errorRate.add(!success);
    responseTime.add(response.timings.duration);
  }

  sleep(Math.random() * 1 + 0.5);
}

export function setup() {
  console.log('Setting up CPU-intensive test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('This test generates CPU-intensive workload to trigger CPU-based autoscaling.');
  console.log('Creating seed user (user_id 1) for follower relationships...');

  return setupSeedUser(BASE_URL);
}

export function teardown(data) {
  console.log('CPU-intensive test completed!');
  console.log('Analyze the results to verify:');
  console.log('- CPU usage reached 70% threshold');
  console.log('- HPA scaled based on CPU (not memory)');
  console.log('- System handled CPU-intensive workload');
}
