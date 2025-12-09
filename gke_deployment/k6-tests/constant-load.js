// k6 Constant Load Test Script
//
// WHAT THIS DOES:
// This script simulates a constant, steady load on the DeathStarBench social network.
// It uses the wrk2-api endpoints which don't require authentication cookies,
// making them ideal for load testing. This test maintains a steady number of
// virtual users to establish baseline performance metrics.
//
// KEY CONCEPTS:
// - Virtual Users (VUs): Simulated users making requests
// - Constant load: Maintains steady number of users (no ramping)
// - Baseline metrics: Establishes normal performance characteristics
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
    { duration: '1m', target: 50 },
    { duration: '1m', target: 50 },
    { duration: '1m', target: 0 },
  ],

  thresholds: {
    'http_req_duration': [
      'p(50)<500',
      'p(95)<1000',
      'p(99)<2000',
    ],
    'http_req_failed': ['rate<0.05'],
    'http_reqs': ['rate>10'],
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

  if (registerResponse.status !== 200 && Math.random() < 0.05) {
    const bodyPreview = registerResponse.body ? registerResponse.body.substring(0, 200) : '(no body)';
    console.log(`[VU ${__VU}] Register: status=${registerResponse.status}, body="${bodyPreview}"`);
  }

  errorRate.add(!registerSuccess);
  responseTime.add(registerResponse.timings.duration);

  if (!registerSuccess) {
    sleep(1);
    return;
  }

  sleep(1);

  const seedUserId = (data && data.seedUserId) || 1;
  const followResponse = ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);

  if (followResponse.status === 200) {
    status200.add(1);
  } else if (followResponse.status >= 500) {
    status500.add(1);
  }

  sleep(0.5);

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

  if (!composeSuccess && Math.random() < 0.01) {
    console.log(`Compose failed: status=${composeResponse.status}, body=${composeResponse.body.substring(0, 200)}`);
  }

  errorRate.add(!composeSuccess);
  responseTime.add(composeResponse.timings.duration);

  sleep(1);

  const timelineResponse = http.get(
    `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${newUser.user_id}&start=0&stop=10`,
    { tags: { name: 'ReadHomeTimeline' } }
  );

  check(timelineResponse, {
    'timeline status is 200': (r) => r.status === 200,
    'timeline response time < 2000ms': (r) => r.timings.duration < 2000,
  });

  sleep(2);
}

export function setup() {
  console.log('Setting up constant load test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log(`Test stages: ${JSON.stringify(options.stages)}`);

  return setupSeedUser(BASE_URL);
}

export function teardown(data) {
  console.log('Constant load test completed!');
  console.log('Check the summary for detailed metrics.');
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
    console.log('  (Unable to read status code counters)');
  }

  console.log(`  200 OK: ${status200Count}`);
  console.log(`  400 Bad Request: ${status400Count}`);
  console.log(`  500+ Server Error: ${status500Count}`);
  console.log(`  Other: ${statusOtherCount}`);

  if (status200Count === 0 && status400Count === 0 && status500Count === 0 && statusOtherCount === 0) {
    console.log('\nNote: Status counters show 0, but check the CUSTOM metrics section above');
    console.log('      for actual status_200 count (should match successful requests)');
  }
}
