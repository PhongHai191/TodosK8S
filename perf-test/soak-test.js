/**
 * SOAK TEST  (Endurance test)
 * Goal    : Run sustained moderate load for 2 hours to surface:
 *   - Memory leaks in the Node.js backend (heap grows without GC)
 *   - PostgreSQL connection pool exhaustion / connection leaks
 *   - Redis connection leaks or stale keys accumulation
 *   - p95 latency degradation over time (should stay flat)
 *   - JWT refresh token TTL issues (tokens expiring mid-run)
 *
 * Duration: ~2 hours 10 minutes
 * Load    : 50 VUs — moderate, not stressful. Goal is time, not scale.
 *
 * Full user lifecycle per iteration (maximises resource usage variety):
 *   login → list todos → create todo → delete todo → refresh token (every 5 iters)
 *
 * Grafana panels to keep open during the run:
 *   - container_memory_working_set_bytes{pod=~"backend.*"}  → should be flat
 *   - pg connection pool metrics (if pg_exporter is set up)
 *   - http_request_duration_seconds p95 over time           → must not drift up
 *   - node_memory_MemAvailable_bytes on k8s-worker-1        → should stay stable
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Gauge } from 'k6/metrics';
import {
  BASE_URL,
  setupUser,
  authHeader,
  getTodos,
  deleteTodo,
  healthCheck,
} from './helpers.js';

const listDuration    = new Trend('soak_list_duration',    true);
const createDuration  = new Trend('soak_create_duration',  true);
const loginDuration   = new Trend('soak_login_duration',   true);
const errorRate       = new Rate('soak_error_rate');

export const options = {
  stages: [
    { duration: '5m',  target: 50 },   // gentle ramp up
    { duration: '2h',  target: 50 },   // sustain — the actual soak
    { duration: '5m',  target: 0  },   // ramp down
  ],
  thresholds: {
    // Strict thresholds — load is light, so any degradation is a red flag
    http_req_duration:   ['p(95)<500', 'p(99)<1000'],
    http_req_failed:     ['rate<0.01'],
    soak_error_rate:     ['rate<0.01'],
    soak_list_duration:  ['p(95)<400'],
    soak_create_duration:['p(95)<500'],
  },
};

export function setup() {
  const h = healthCheck();
  console.log(`Pre-soak health: ${h.status} ${h.body}`);
  if (h.status !== 200) {
    console.error('Cluster is not healthy — aborting soak test is recommended');
  }
}

// Per-VU state
let accessToken  = null;
let refreshToken = null;

export default function () {
  // ── Lazy init: register + login once per VU ───────────────────────────────
  if (!accessToken) {
    const session = setupUser(`soak_vu${__VU}`);
    if (!session) { sleep(5); return; }
    accessToken  = session.accessToken;
    refreshToken = session.refreshToken;
  }

  const headers = authHeader(accessToken);

  // ── Step 1: List todos (Redis cache hit most of the time) ─────────────────
  const listRes = getTodos(accessToken);
  listDuration.add(listRes.timings.duration);
  const listOk = check(listRes, {
    'soak list: 200':          (r) => r.status === 200,
    'soak list: array body':   (r) => Array.isArray(r.json()),
    'soak list: duration<800': (r) => r.timings.duration < 800,
  });
  errorRate.add(!listOk);
  sleep(1);

  // ── Step 2: Create todo (DB write + Redis cache invalidation) ─────────────
  const createRes = http.post(
    `${BASE_URL}/api/todos`,
    JSON.stringify({ text: `Soak VU${__VU} iter${__ITER} t=${Date.now()}` }),
    { headers },
  );
  createDuration.add(createRes.timings.duration);
  const createOk = check(createRes, {
    'soak create: 201':          (r) => r.status === 201,
    'soak create: has id':       (r) => r.json('id') !== undefined,
    'soak create: duration<800': (r) => r.timings.duration < 800,
  });
  errorRate.add(!createOk);
  sleep(1);

  // ── Step 3: Delete the created todo (prevent unbounded DB growth) ─────────
  if (createOk) {
    const id = createRes.json('id');
    const delRes = deleteTodo(accessToken, id);
    check(delRes, { 'soak delete: 204': (r) => r.status === 204 });
    errorRate.add(delRes.status !== 204);
  }
  sleep(1);

  // ── Step 4: Refresh access token every 5 iterations ──────────────────────
  // Access tokens expire (ACCESS_EXPIRE env). Refreshing exercises:
  //   - Redis lookup of refresh token
  //   - JWT sign of new access token
  //   - Redis write of new refresh token
  if (__ITER > 0 && __ITER % 5 === 0 && refreshToken) {
    const refreshRes = http.post(
      `${BASE_URL}/api/auth/refresh`,
      JSON.stringify({ refreshToken }),
      { headers: { 'Content-Type': 'application/json' } },
    );
    loginDuration.add(refreshRes.timings.duration);
    const refreshOk = check(refreshRes, {
      'soak refresh: 200':      (r) => r.status === 200,
      'soak refresh: has token':(r) => r.json('accessToken') !== undefined,
    });
    errorRate.add(!refreshOk);

    if (refreshOk) {
      accessToken = refreshRes.json('accessToken');
    } else {
      // Token likely expired or Redis lost state — re-login
      console.warn(`VU${__VU} refresh failed (${refreshRes.status}), re-logging in`);
      const session = setupUser(`soak_vu${__VU}`);
      if (session) {
        accessToken  = session.accessToken;
        refreshToken = session.refreshToken;
      }
    }
    sleep(1);
  }

  // ── Step 5: Health check (sample every 20 iterations per VU) ─────────────
  // Ensures /health/db (DB + Redis connectivity) stays green throughout the run
  if (__ITER % 20 === 0) {
    const h = healthCheck();
    check(h, {
      'soak health: 200':    (r) => r.status === 200,
      'soak health: status': (r) => {
        try { return r.json('status') === 'OK'; } catch { return false; }
      },
    });
    errorRate.add(h.status !== 200);
  }

  sleep(2);  // total ~7 s per iteration at 50 VUs → ~350 req/min baseline
}
