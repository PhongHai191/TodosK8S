/**
 * STRESS TEST
 * Goal    : Find the breaking point — the VU count at which the system starts failing
 *           or violating latency budgets. NOT expected to pass all thresholds.
 * Duration: ~17 minutes
 *
 * Strategy:
 *   Ramp VUs from normal load (100) up to extreme load (500) in steps,
 *   then ramp down to observe whether the system self-recovers.
 *
 * Key signals to watch (Grafana while running):
 *   - node-exporter CPU on k8s-worker-1 → when does it saturate?
 *   - kube-state-metrics pod restarts   → OOMKilled?
 *   - prom metric http_request_duration_seconds → latency climb
 *   - Loki logs → 5xx errors, pool exhaustion from pg/redis
 *
 * API under test:
 *   POST /api/auth/login — heaviest endpoint:
 *     bcrypt compare (CPU-bound) + DB query + Redis write + JWT sign
 *   GET /api/todos       — DB + Redis + JWT verify
 *
 * setup() pre-creates 500 accounts BEFORE any VU spawns so register calls
 * don't pollute the stress metrics.
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';
import { BASE_URL, setupUser, authHeader, getTodos, healthCheck } from './helpers.js';

const loginDuration = new Trend('stress_login_duration', true);
const listDuration  = new Trend('stress_list_duration',  true);
const errorRate     = new Rate('stress_error_rate');

// Max VUs across all stages
const MAX_VUS = 500;

export const options = {
  stages: [
    { duration: '2m',  target: 100 },  // warm up at expected peak
    { duration: '3m',  target: 200 },  // begin stress
    { duration: '3m',  target: 300 },  // push harder
    { duration: '3m',  target: 400 },  // heavy stress
    { duration: '3m',  target: 500 },  // extreme — find breaking point
    { duration: '3m',  target: 0   },  // ramp down — observe recovery
  ],
  thresholds: {
    http_req_failed:      ['rate<0.15'],   // alert only on >15% errors
    stress_error_rate:    ['rate<0.15'],
    http_req_duration:    ['p(99)<5000'],  // tolerate up to 5 s under extreme load
  },
};

/**
 * Pre-create all accounts before any VU spawns.
 * Returns tokens array — each VU gets its token by index so the first
 * iteration doesn't spend time on register/login.
 */
export function setup() {
  const h = healthCheck();
  console.log(`Pre-stress health: ${h.status} ${h.body}`);

  console.log(`Pre-creating ${MAX_VUS} stress accounts...`);
  const tokens = [];
  for (let i = 1; i <= MAX_VUS; i++) {
    const session = setupUser(`stress_vu${i}`);
    if (!session) {
      console.error(`Failed to setup stress_vu${i}`);
      return { tokens };
    }
    tokens.push(session.accessToken);
  }
  console.log(`Setup complete: ${tokens.length} accounts ready`);
  return { tokens };
}

export default function (data) {
  // Pick initial token by VU index — avoids lazy-init login in hot path
  let token = data.tokens[__VU - 1];
  if (!token) {
    console.error(`No token for VU ${__VU} — skipping`);
    return;
  }

  // Re-login every 10th iteration to stress the auth path (bcrypt + DB + Redis + JWT)
  // This is intentional: we want to measure auth under concurrent load
  const shouldReLogin = __ITER % 10 === 0;

  if (shouldReLogin) {
    const loginRes = http.post(
      `${BASE_URL}/api/auth/login`,
      JSON.stringify({ username: `stress_vu${__VU}`, password: 'Perf@1234!' }),
      { headers: { 'Content-Type': 'application/json' } },
    );
    loginDuration.add(loginRes.timings.duration);
    const loginOk = check(loginRes, {
      'login: not 5xx':    (r) => r.status < 500,
      'login: status 200': (r) => r.status === 200,
      'login: has token':  (r) => r.json('accessToken') !== undefined,
    });
    errorRate.add(!loginOk);

    if (loginRes.status === 200) {
      token = loginRes.json('accessToken');
    }
    sleep(0.5);
  }

  // ── API stress: list todos (DB read + Redis cache + JWT verify) ───────────
  const listRes = getTodos(token);
  listDuration.add(listRes.timings.duration);
  const listOk = check(listRes, {
    'list: not 5xx':    (r) => r.status < 500,
    'list: status 200': (r) => r.status === 200,
  });
  errorRate.add(!listOk);
  sleep(0.5);

  // ── Write stress: create todo (DB write + cache invalidation) ─────────────
  const createRes = http.post(
    `${BASE_URL}/api/todos`,
    JSON.stringify({ text: `Stress ${__VU}-${__ITER}` }),
    { headers: authHeader(token) },
  );
  const createOk = check(createRes, {
    'create: not 5xx': (r) => r.status < 500,
    'create: 201':     (r) => r.status === 201,
  });
  errorRate.add(!createOk);

  sleep(0.5);
}
