/**
 * LOAD TEST
 * Goal    : Confirm the system handles expected normal traffic (50→100 VUs) within SLA.
 * Duration: ~13 minutes
 * Thresholds:
 *   - p(95) latency < 300 ms
 *   - p(99) latency < 500 ms
 *   - error rate   < 1 %
 *
 * Flow per VU (realistic user session):
 *   1. setup() pre-creates 100 accounts + tokens BEFORE any VU spawns (not counted in metrics)
 *   2. Each VU picks its token from the shared array by index (__VU - 1)
 *   3. List todos   → cache hit after first request (Redis TTL 60 s)
 *   4. Create todo  → invalidates Redis cache
 *   5. Delete todo  → cleanup so DB stays stable across runs
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { BASE_URL, setupUser, authHeader, getTodos, deleteTodo, healthCheck } from './helpers.js';

const listDuration   = new Trend('todo_list_duration',   true);
const createDuration = new Trend('todo_create_duration', true);
const deleteDuration = new Trend('todo_delete_duration', true);
const errorRate      = new Rate('load_error_rate');
const todosCreated   = new Counter('todos_created');

// Max VUs across all stages — pre-create exactly this many accounts in setup()
const MAX_VUS = 100;

export const options = {
  stages: [
    { duration: '1m',  target: 50  },  // ramp up to normal load
    { duration: '5m',  target: 50  },  // sustain
    { duration: '1m',  target: 100 },  // scale to peak
    { duration: '5m',  target: 100 },  // sustain
    { duration: '1m',  target: 0   },  // ramp down
  ],
  thresholds: {
    http_req_duration:    ['p(95)<300', 'p(99)<500'],
    http_req_failed:      ['rate<0.01'],
    load_error_rate:      ['rate<0.01'],
    todo_list_duration:   ['p(95)<300'],
    todo_create_duration: ['p(95)<400'],
  },
};

/**
 * setup() runs ONCE, single-threaded, BEFORE any VU spawns.
 * HTTP calls here are NOT counted in test metrics.
 * Returns a value that k6 passes as the first arg to default() and teardown().
 */
export function setup() {
  // 1. Cluster health check
  const h = healthCheck();
  if (h.status !== 200) {
    console.warn(`/health/db returned ${h.status} — cluster may be degraded`);
  }

  // 2. Pre-create MAX_VUS accounts sequentially, collect their tokens
  console.log(`Pre-creating ${MAX_VUS} test accounts...`);
  const tokens = [];
  for (let i = 1; i <= MAX_VUS; i++) {
    const session = setupUser(`load_vu${i}`);
    if (!session) {
      console.error(`Failed to setup load_vu${i} — aborting`);
      // Return what we have; VUs beyond tokens.length will be skipped
      return { tokens };
    }
    tokens.push(session.accessToken);
  }
  console.log(`Setup complete: ${tokens.length} accounts ready`);
  return { tokens };
}

export default function (data) {
  // Each VU picks its own token by index — __VU starts at 1
  const token = data.tokens[__VU - 1];
  if (!token) {
    console.error(`No token for VU ${__VU} — skipping iteration`);
    return;
  }

  const headers = authHeader(token);

  // ── 1. List todos ──────────────────────────────────────────────────────────
  const listRes = getTodos(token);
  listDuration.add(listRes.timings.duration);
  const listOk = check(listRes, {
    'list: 200':           (r) => r.status === 200,
    'list: array body':    (r) => Array.isArray(r.json()),
    'list: duration<500':  (r) => r.timings.duration < 500,
  });
  errorRate.add(!listOk);
  sleep(1);

  // ── 2. Create todo ─────────────────────────────────────────────────────────
  const createRes = http.post(
    `${BASE_URL}/api/todos`,
    JSON.stringify({ text: `Load task ${Date.now()}` }),
    { headers },
  );
  createDuration.add(createRes.timings.duration);
  const createOk = check(createRes, {
    'create: 201':          (r) => r.status === 201,
    'create: has id':       (r) => r.json('id') !== undefined,
    'create: duration<500': (r) => r.timings.duration < 500,
  });
  errorRate.add(!createOk);

  if (createOk) {
    todosCreated.add(1);
    sleep(0.5);

    // ── 3. Delete todo (keep DB size stable across runs) ──────────────────
    const id = createRes.json('id');
    const delRes = deleteTodo(token, id);
    deleteDuration.add(delRes.timings.duration);
    check(delRes, { 'delete: 204': (r) => r.status === 204 });
  }

  sleep(1);
}
