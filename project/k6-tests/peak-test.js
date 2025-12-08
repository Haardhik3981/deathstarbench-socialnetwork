// k6 Peak/Spike Test Script
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

export const options = {
  stages: [
    { duration: '2m', target: 50 },
    { duration: '2m', target: 1000 },
    { duration: '2m', target: 500 },
    { duration: '2m', target: 100 },
    { duration: '2m', target: 50 },
    { duration: '1m', target: 0 },
  ],

  thresholds: {
    'http_req_duration': [
      'p(50)<800',
      'p(95)<2000',
      'p(99)<5000',
    ],
    'http_req_failed': ['rate<0.20'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function (data) {
  const newUser = generateRandomUser();
  const registerResponse = registerUser(BASE_URL, newUser);

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

  errorRate.add(!registerSuccess);
  responseTime.add(registerResponse.timings.duration);

  if (!registerSuccess) {
    sleep(0.5);
    return;
  }

  sleep(Math.random() * 0.5);

  const seedUserId = (data && data.seedUserId) || 1;
  const followResponse = ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);

  if (followResponse.status === 200) {
    status200.add(1);
  } else if (followResponse.status >= 500) {
    status500.add(1);
  }

  sleep(0.2);

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

  if (composeResponse.status === 200) {
    status200.add(1);
  } else if (composeResponse.status === 400) {
    status400.add(1);
  } else if (composeResponse.status >= 500) {
    status500.add(1);
  } else {
    statusOther.add(1);
  }

  errorRate.add(!composeSuccess);
  responseTime.add(composeResponse.timings.duration);

  sleep(0.3);

  const timelineResponse = http.get(
    `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${newUser.user_id}&start=0&stop=10`,
    { tags: { name: 'ReadHomeTimeline' } }
  );

  check(timelineResponse, {
    'timeline status is 200': (r) => r.status === 200,
    'timeline response time < 2000ms': (r) => r.timings.duration < 2000,
  });

  sleep(Math.random() * 0.5);
}

export function setup() {
  console.log('Setting up peak/spike test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('This test will simulate a traffic spike (1000 VUs peak).');
  console.log('Gradual ramp-up allows autoscaling to respond.');
  console.log('Creating seed user (user_id 1) for follower relationships...');

  return setupSeedUser(BASE_URL);
}

export function teardown(data) {
  console.log('Peak test completed!');
  console.log('Analyze the results to see:');
  console.log('- When autoscaling triggered');
  console.log('- Which endpoints failed first');
  console.log('- Recovery time after spike');
  console.log('\nStatus Code Summary:');

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
