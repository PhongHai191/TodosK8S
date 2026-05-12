/**
 * SPIKE TEST
 * Goal    : Simulate a sudden, massive traffic burst (e.g. all users login at once)
 *           and verify the system either handles it gracefully or recovers quickly.
 * Duration: ~7 minutes
 *
 * Traffic pattern:
 *   Idle baseline → instant spike to 400 VUs → sustain → instant drop → recovery check
 *
 * Key signals:
 *   - Does ingress-nginx return 502/503 during the spike?
 *   - Do backend pods get OOMKilled? (kubectl get events -n todoapp)
 *   - Does p95 latency return to baseline after the spike drops?
 *   - Does Redis connection pool survive the burst?
 *
 * API under test:
 *   POST /api/auth/login — most likely endpoint to be hit in a real spike
 *     (users all logging in simultaneously — login per iteration is intentional)
 *   GET  /api/todos      — immediately after login
 *
 * Why login every iteration here (unlike stress-test):
 *   Spike scenario = everyone logs in at the same moment. The login call
 *   IS the spike traffic, not a side effect. We pre-create accounts in setup()
 *   so register calls don't pollute metrics, but we deliberately hit /login
 *   on every iteration to generate realistic spike load on bcrypt + DB + Redis.
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';
import { BASE_URL, batchSetupUsers, getTodos, healthCheck } from './helpers.js';

const loginDuration   = new Trend('spike_login_duration',   true);
const listDuration    = new Trend('spike_list_duration',    true);
const errorRate       = new Rate('spike_error_rate');
const recoveryLatency = new Trend('spike_recovery_latency', true);

// Max VUs across all stages
const MAX_VUS = 400;

export const options = {
  setupTimeout: '3m',  // 400 accounts × ~2 req each — needs more than default 60s
  stages: [
    { duration: '30s', target: 10  },  // baseline — idle
    { duration: '10s', target: 400 },  // SPIKE UP — instant burst
    { duration: '1m',  target: 400 },  // sustain spike
    { duration: '10s', target: 10  },  // SPIKE DOWN — instant drop
    { duration: '3m',  target: 10  },  // recovery observation window
    { duration: '30s', target: 0   },  // ramp down
  ],
  thresholds: {
    http_req_failed:          ['rate<0.20'],  // tolerate 20% error during spike
    spike_error_rate:         ['rate<0.20'],
    spike_recovery_latency:   ['p(95)<400'],  // must recover after spike drops
  },
};

/**
 * Pre-create accounts only — no need to fetch tokens since login
 * every iteration is the whole point of this test.
 */
export function setup() {
  const h = healthCheck();
  console.log(`Pre-spike health: ${h.status} ${h.body}`);

  // Register only (returnTokens=false) — login per iteration is intentional
  console.log(`Pre-creating ${MAX_VUS} spike accounts in parallel batches...`);
  batchSetupUsers('spike_vu', MAX_VUS, 50, false);
  console.log('Spike accounts ready');
}

export default function () {
  // VUs above MAX_VUS shouldn't happen given our stages, but guard anyway
  if (__VU > MAX_VUS) {
    console.error(`VU ${__VU} exceeds MAX_VUS ${MAX_VUS}`);
    return;
  }

  // Recovery phase: VU count has dropped back to ~10
  const isRecoveryPhase = __VU <= 15;

  // ── Login every iteration — this IS the spike load ────────────────────────
  // Simulates all users authenticating simultaneously during a traffic burst.
  // Hits: bcrypt.compare (CPU) + DB query + Redis write + JWT sign
  const loginRes = http.post(
    `${BASE_URL}/api/auth/login`,
    JSON.stringify({ username: `spike_vu${__VU}`, password: 'Perf@1234!' }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  loginDuration.add(loginRes.timings.duration);
  if (isRecoveryPhase) recoveryLatency.add(loginRes.timings.duration);

  const loginOk = check(loginRes, {
    'login: not 5xx':   (r) => r.status < 500,
    'login: has token': (r) => r.status === 200 && r.json('accessToken') !== undefined,
  });
  errorRate.add(!loginOk);

  if (!loginOk) { sleep(1); return; }

  const token = loginRes.json('accessToken');
  sleep(0.2);  // minimal think time — spike users act immediately after login

  // ── First action after login: list todos ──────────────────────────────────
  const listRes = getTodos(token);
  listDuration.add(listRes.timings.duration);
  if (isRecoveryPhase) recoveryLatency.add(listRes.timings.duration);

  const listOk = check(listRes, {
    'list: not 5xx':    (r) => r.status < 500,
    'list: status 200': (r) => r.status === 200,
  });
  errorRate.add(!listOk);

  // Recovery phase: longer sleep to reduce pressure and get clean latency readings
  sleep(isRecoveryPhase ? 2 : 0.5);
}
