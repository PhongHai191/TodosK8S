import http from 'k6/http';
import { check } from 'k6';

export const BASE_URL = __ENV.BASE_URL || 'http://192.168.241.10:30080';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

// Register + login a user, return { accessToken, refreshToken }
// username must be unique per VU to avoid conflicts across parallel VUs
export function setupUser(username, password = 'Perf@1234!') {
  // Register (ignore 400 — user may already exist from a prior run)
  http.post(
    `${BASE_URL}/api/auth/register`,
    JSON.stringify({ username, password }),
    { headers: JSON_HEADERS },
  );

  const res = http.post(
    `${BASE_URL}/api/auth/login`,
    JSON.stringify({ username, password }),
    { headers: JSON_HEADERS },
  );

  check(res, { 'setup: login ok': (r) => r.status === 200 });

  if (res.status !== 200) {
    console.error(`setupUser failed for ${username}: ${res.status} ${res.body}`);
    return null;
  }

  return res.json();   // { accessToken, refreshToken }
}

// Return Authorization header object from an accessToken string
export function authHeader(token) {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

// Login only (for scenarios that create fresh sessions each iteration)
export function login(username, password = 'Perf@1234!') {
  return http.post(
    `${BASE_URL}/api/auth/login`,
    JSON.stringify({ username, password }),
    { headers: JSON_HEADERS },
  );
}

// GET /api/todos
export function getTodos(token) {
  return http.get(`${BASE_URL}/api/todos`, { headers: authHeader(token) });
}

// POST /api/todos  →  returns created todo or null
export function createTodo(token, text) {
  const res = http.post(
    `${BASE_URL}/api/todos`,
    JSON.stringify({ text }),
    { headers: authHeader(token) },
  );
  if (res.status === 201) return res.json();
  return null;
}

// DELETE /api/todos/:id
export function deleteTodo(token, id) {
  return http.del(`${BASE_URL}/api/todos/${id}`, null, { headers: authHeader(token) });
}

// GET /health/db
export function healthCheck() {
  return http.get(`${BASE_URL}/health/db`);
}

/**
 * Pre-create `count` accounts in parallel using http.batch().
 * Sends `batchSize` register requests simultaneously, then `batchSize` login
 * requests — dramatically faster than sequential setupUser() calls.
 *
 * @param {string} prefix   - username prefix, e.g. "stress_vu" → "stress_vu1"
 * @param {number} count    - total accounts to create
 * @param {number} batchSize - concurrent requests per batch (default 50)
 * @param {boolean} returnTokens - if true, return accessTokens array; if false return empty array
 * @returns {string[]} accessTokens (empty array if returnTokens=false)
 */
export function batchSetupUsers(prefix, count, batchSize = 50, returnTokens = true) {
  const password = 'Perf@1234!';
  const tokens = [];

  for (let start = 1; start <= count; start += batchSize) {
    const end = Math.min(start + batchSize - 1, count);

    // ── 1. Batch register ────────────────────────────────────────────────────
    const registerRequests = [];
    for (let i = start; i <= end; i++) {
      registerRequests.push({
        method: 'POST',
        url: `${BASE_URL}/api/auth/register`,
        body: JSON.stringify({ username: `${prefix}${i}`, password }),
        params: { headers: JSON_HEADERS },
      });
    }
    // ignore register responses — 400 means account already exists (idempotent)
    http.batch(registerRequests);

    if (!returnTokens) continue;

    // ── 2. Batch login ───────────────────────────────────────────────────────
    const loginRequests = [];
    for (let i = start; i <= end; i++) {
      loginRequests.push({
        method: 'POST',
        url: `${BASE_URL}/api/auth/login`,
        body: JSON.stringify({ username: `${prefix}${i}`, password }),
        params: { headers: JSON_HEADERS },
      });
    }
    const loginResponses = http.batch(loginRequests);

    for (const res of loginResponses) {
      if (res.status === 200) {
        tokens.push(res.json('accessToken'));
      } else {
        console.error(`batch login failed: ${res.status} ${res.body}`);
        tokens.push(null);
      }
    }

    console.log(`Setup progress: ${Math.min(end, count)}/${count} accounts ready`);
  }

  return tokens;
}
