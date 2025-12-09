// k6 Quick Test Script
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

const errorRate = new Rate('errors');
const responseTime = new Trend('response_time');

export const options = {
  vus: 10,
  duration: '20s',

  thresholds: {
    'http_req_duration': [
      'p(50)<500',
      'p(95)<1000',
      'p(99)<2000',
    ],
    'http_req_failed': ['rate<0.05'],
    'http_reqs': ['rate>1'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function (data) {
  const newUser = generateRandomUser();
  const registerResponse = registerUser(BASE_URL, newUser);

  const registerSuccess = check(registerResponse, {
    'register status is 200': (r) => r.status === 200,
    'register response time < 2000ms': (r) => r.timings.duration < 2000,
  });

  errorRate.add(!registerSuccess);
  responseTime.add(registerResponse.timings.duration);

  if (!registerSuccess) {
    sleep(0.5);
    return;
  }

  sleep(0.5);

  const seedUserId = (data && data.seedUserId) || 1;
  ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);
  sleep(0.3);

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

  const timelineResponse = http.get(
    `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${newUser.user_id}&start=0&stop=10`,
    { tags: { name: 'ReadHomeTimeline' } }
  );

  check(timelineResponse, {
    'timeline status is 200': (r) => r.status === 200,
    'timeline response time < 2000ms': (r) => r.timings.duration < 2000,
  });

  sleep(0.5);
}

export function setup() {
  console.log('Setting up quick validation test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log(`Virtual Users: ${options.vus}`);
  console.log(`Duration: ${options.duration}`);
  console.log('This is a quick test to validate metrics collection.');

  return setupSeedUser(BASE_URL);
}

export function teardown(data) {
  console.log('Quick test completed!');
  console.log('Check the metrics CSV file to verify all values are being recorded correctly.');
}
