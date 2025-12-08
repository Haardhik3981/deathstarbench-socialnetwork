// k6 Sweet Spot Test Script
//
// WHAT THIS DOES:
// This script simulates a challenging but achievable load that demonstrates
// autoscaling working correctly. It's designed to be more aggressive than
// constant-load but more reasonable than peak-test, finding the "sweet spot"
// where autoscaling is clearly visible and the system performs well.
//
// KEY CONCEPTS:
// - Gradual ramp-up: Allows autoscaling to respond naturally
// - Sustained peak: Maintains load long enough to observe scaling behavior
// - Gradual ramp-down: Tests recovery and scale-down behavior
// - Achievable load: High enough to trigger scaling, low enough to succeed
//
// WHY WE USE IT:
// Sweet spot testing helps us understand:
// - Autoscaling effectiveness (does it scale when needed?)
// - System performance under challenging but sustainable load
// - Recovery behavior after load decreases
// - Real-world performance characteristics (not extreme failure scenarios)

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
    { duration: '1m30s', target: 50 },
    { duration: '1m30s', target: 200 },
    { duration: '2m', target: 400 },
    { duration: '2m', target: 600 },
    { duration: '2m', target: 800 },
    { duration: '2m', target: 1000 },
    { duration: '2m', target: 800 },
    { duration: '2m', target: 600 },
    { duration: '2m', target: 400 },
    { duration: '1m30s', target: 200 },
    { duration: '1m', target: 50 },
    { duration: '30s', target: 0 },
  ],

  thresholds: {
    'http_req_duration': [
      'p(50)<800',
      'p(95)<2000',
      'p(99)<4000',
    ],
    'http_req_failed': ['rate<0.15'],
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
    'register response time < 3000ms': (r) => r.timings.duration < 3000,
  });

  errorRate.add(!registerSuccess);
  responseTime.add(registerResponse.timings.duration);

  if (!registerSuccess) {
    sleep(0.5);
    return;
  }

  sleep(Math.random() * 0.0 + 0.5);

  const seedUserId = (data && data.seedUserId) || 1;
  const followResponse = ensureUserHasFollower(BASE_URL, newUser.user_id, seedUserId);

  if (followResponse.status === 200) {
    status200.add(1);
  } else if (followResponse.status >= 500) {
    status500.add(1);
  }

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
    'compose response time < 3000ms': (r) => r.timings.duration < 3000,
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

  sleep(0.5);

  const timelineResponse = http.get(
    `${BASE_URL}/wrk2-api/home-timeline/read?user_id=${newUser.user_id}&start=0&stop=10`,
    { tags: { name: 'ReadHomeTimeline' } }
  );

  const timelineSuccess = check(timelineResponse, {
    'timeline status is 200': (r) => r.status === 200,
    'timeline response time < 3000ms': (r) => r.timings.duration < 3000,
  });

  if (timelineResponse.status === 200) {
    status200.add(1);
  } else if (timelineResponse.status >= 500) {
    status500.add(1);
  }

  errorRate.add(!timelineSuccess);
  responseTime.add(timelineResponse.timings.duration);

  sleep(Math.random() * 1.5 + 0.5);
}

export function setup() {
  console.log('Setting up sweet spot test...');
  console.log(`Target URL: ${BASE_URL}`);
  console.log('This test demonstrates autoscaling under challenging but achievable load.');
  console.log('Expected behavior:');
  console.log('  - Gradual ramp-up allows autoscaling to respond');
  console.log('  - Peak load (1000 VUs) triggers scaling without overwhelming system');
  console.log('  - System maintains good performance (>85% success rate)');
  console.log('  - Gradual ramp-down shows scale-down behavior');
  console.log('Creating seed user (user_id 1) for follower relationships...');

  return setupSeedUser(BASE_URL);
}

export function teardown(data) {
  console.log('Sweet spot test completed!');
  console.log('Analyze the results to see:');
  console.log('- Autoscaling triggered during ramp-up (check pod counts)');
  console.log('- System performance maintained under peak load');
  console.log('- Success rate should be >85% (challenging but achievable)');
  console.log('- Scale-down behavior during ramp-down');
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

  if (status200Count > 0) {
    const total = status200Count + status400Count + status500Count + statusOtherCount;
    const successRate = ((status200Count / total) * 100).toFixed(2);
    console.log(`\nSuccess Rate: ${successRate}%`);
    if (parseFloat(successRate) >= 85) {
      console.log('✓ Excellent! System handled challenging load well.');
    } else if (parseFloat(successRate) >= 70) {
      console.log('⚠ Acceptable, but system struggled under load.');
    } else {
      console.log('✗ System struggled significantly under load.');
    }
  }
}
