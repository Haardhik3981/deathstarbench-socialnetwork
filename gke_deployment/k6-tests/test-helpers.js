// Shared helper functions for k6 tests
// These functions ensure tests avoid edge cases that cause errors

import http from 'k6/http';

// Helper function to encode form data
export function encodeFormData(data) {
  return Object.keys(data)
    .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(data[key])}`)
    .join('&');
}

// Helper function to generate random user data
export function generateRandomUser() {
  const id = Math.floor(Math.random() * 1000000);
  const username = `user_${id}_${Date.now()}`;
  return {
    user_id: id,
    username: username,
    first_name: `FirstName${id}`,
    last_name: `LastName${id}`,
    password: `password${id}`,
  };
}

// Helper function to register a user
export function registerUser(baseUrl, user) {
  const registerPayload = {
    user_id: user.user_id.toString(),
    username: user.username,
    first_name: user.first_name,
    last_name: user.last_name,
    password: user.password,
  };
  
  return http.post(
    `${baseUrl}/wrk2-api/user/register`,
    encodeFormData(registerPayload),
    {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      tags: { name: 'RegisterUser' }
    }
  );
}

// Helper function to ensure a user has at least one follower
// This prevents "ZADD: no key specified" errors when composing posts
// Strategy: Have a seed user (user_id 1) follow the new user
export function ensureUserHasFollower(baseUrl, userId, seedUserId = 1) {
  const followPayload = {
    user_id: seedUserId.toString(),
    followee_id: userId.toString(),
  };
  
  const followResponse = http.post(
    `${baseUrl}/wrk2-api/user/follow`,
    encodeFormData(followPayload),
    {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      tags: { name: 'FollowUser' }
    }
  );
  
  return followResponse;
}

// Helper function to generate random post data
export function generateRandomPost(userId, username) {
  const postTypes = [0, 1, 2]; // Different post types
  return {
    user_id: userId,
    username: username,
    post_type: postTypes[Math.floor(Math.random() * postTypes.length)],
    text: `This is a test post from user ${username} at ${new Date().toISOString()}`,
    media_ids: JSON.stringify([]),
    media_types: JSON.stringify([]),
  };
}

// Helper function to compose a post (with follower check)
export function composePost(baseUrl, user, postData) {
  // First ensure user has a follower to avoid ZADD errors
  ensureUserHasFollower(baseUrl, user.user_id);
  
  // Then compose the post
  return http.post(
    `${baseUrl}/wrk2-api/post/compose`,
    encodeFormData(postData),
    {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      tags: { name: 'ComposePost' }
    }
  );
}

// Setup function to create seed user (call this in test setup)
export function setupSeedUser(baseUrl) {
  const seedUser = {
    user_id: 1,
    username: 'seed_user_1',
    first_name: 'Seed',
    last_name: 'User',
    password: 'seedpassword123',
  };
  
  const seedRegisterPayload = {
    user_id: seedUser.user_id.toString(),
    username: seedUser.username,
    first_name: seedUser.first_name,
    last_name: seedUser.last_name,
    password: seedUser.password,
  };
  
  console.log('Creating seed user (user_id 1) for follower relationships...');
  const seedRegisterResponse = http.post(
    `${baseUrl}/wrk2-api/user/register`,
    encodeFormData(seedRegisterPayload),
    {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      tags: { name: 'RegisterSeedUser' }
    }
  );
  
  if (seedRegisterResponse.status === 200) {
    console.log('✓ Seed user created successfully');
  } else if (seedRegisterResponse.status === 400) {
    // User might already exist, that's okay
    console.log('ℹ Seed user may already exist (status 400)');
  } else {
    console.log(`⚠ Seed user creation returned status ${seedRegisterResponse.status}`);
  }
  
  return {
    seedUserId: seedUser.user_id,
  };
}

