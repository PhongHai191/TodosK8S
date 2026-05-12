# Performance Tests — TodoK8s

k6-based performance test suite covering four test types against the TodoK8s ingress at `http://192.168.241.10:30080`.

## Prerequisites

```bash
# Install k6 (Windows)
winget install k6 --source winget

# Or via WSL2 / Linux
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6
```

## Files

| File | Purpose |
|---|---|
| `helpers.js` | Shared utilities: `setupUser`, `authHeader`, `getTodos`, `createTodo`, `deleteTodo`, `healthCheck` |
| `load-test.js` | Normal expected traffic |
| `stress-test.js` | Find the breaking point |
| `spike-test.js` | Sudden traffic burst + recovery |
| `soak-test.js` | 2-hour endurance run |

## Running Tests

All tests accept `BASE_URL` as an env var (default: `http://192.168.241.10:30080`).

```bash
cd perf-test

# 1. Load test (~13 min)
k6 run load-test.js

# 2. Stress test (~17 min)
k6 run stress-test.js

# 3. Spike test (~7 min)
k6 run spike-test.js

# 4. Soak test (~2h 10 min) — run in background
nohup k6 run soak-test.js > results/soak-$(date +%Y%m%d-%H%M).log 2>&1 &

# Override target host
k6 run -e BASE_URL=http://192.168.241.11:30080 load-test.js

# Save summary JSON for comparison
k6 run --summary-export=results/load-$(date +%Y%m%d).json load-test.js
```

## Recommended Run Order

```
1. load-test   → establish baseline, confirm SLA thresholds pass
2. stress-test → identify breaking point before going further
3. spike-test  → validate recovery behavior
4. soak-test   → run last; takes the longest
```

## Thresholds Summary

| Test | p(95) | p(99) | Error rate |
|---|---|---|---|
| Load | < 300 ms | < 500 ms | < 1 % |
| Stress | — | < 5000 ms | < 15 % |
| Spike | — | — | < 20 % |
| Soak | < 500 ms | < 1000 ms | < 1 % |

## Observing Results in Grafana

While any test runs, open Grafana at `http://192.168.241.10:30000` and watch:

- **Node CPU** (`node_cpu_seconds_total`) on `k8s-worker-1` — backend saturation
- **Pod memory** (`container_memory_working_set_bytes`) — OOM risk / memory leaks
- **HTTP latency** (`http_request_duration_seconds`) — p95/p99 trend
- **Pod restarts** (`kube_pod_container_status_restarts_total`) — crash loops
- **Loki logs** — filter `namespace=todoapp` for 5xx errors

```bash
# Watch pods in parallel while a test runs
kubectl get pods -n todoapp -w

# Check events for OOMKilled / back-off
kubectl get events -n todoapp --sort-by='.lastTimestamp'
```

## Test Accounts

Each test creates VU-scoped accounts with the pattern:

| Test | Username pattern | Password |
|---|---|---|
| Load | `load_vu<N>` | `Perf@1234!` |
| Stress | `stress_vu<N>` | `Perf@1234!` |
| Spike | `spike_vu<N>` | `Perf@1234!` |
| Soak | `soak_vu<N>` | `Perf@1234!` |

Accounts are created on first use and reused on subsequent runs (`register` returns 400 on duplicate — ignored). Clean up with:

```sql
-- Run against RDS after testing
DELETE FROM users WHERE username LIKE 'load_vu%'
  OR username LIKE 'stress_vu%'
  OR username LIKE 'spike_vu%'
  OR username LIKE 'soak_vu%';
```
