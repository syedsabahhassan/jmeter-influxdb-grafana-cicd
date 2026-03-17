# JMeter + InfluxDB + Grafana CI/CD Pipeline

[![Performance Tests](https://img.shields.io/badge/Performance%20Tests-JMeter%205.6.3-orange?logo=apache)](https://jmeter.apache.org/)
[![Monitoring](https://img.shields.io/badge/Monitoring-InfluxDB%201.8%20%2B%20Grafana%2010-blue?logo=grafana)](https://grafana.com/)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-black?logo=github-actions)](https://github.com/features/actions)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)](https://docs.docker.com/compose/)

A **portfolio-grade performance testing pipeline** demonstrating real-time metrics streaming from Apache JMeter into InfluxDB, visualised live in Grafana — all wired together in a GitHub Actions CI/CD workflow.

**Target API:** [JSONPlaceholder](https://jsonplaceholder.typicode.com) (public mock REST API — swap for your own via `--url`).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Actions Pipeline                       │
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐ │
│  │  JMeter 5.6.3 │────▶│  InfluxDB 1.8│────▶│  Grafana 10.2    │ │
│  │              │     │  (jmeter db) │     │  (Dashboard)     │ │
│  │  Load Test   │     │              │     │                  │ │
│  │  Stress Test │     │  Time-series │     │  Real-time       │ │
│  │  Spike Test  │     │  metrics     │     │  charts, SLA     │ │
│  └──────────────┘     └──────────────┘     │  gauges, tables  │ │
│         │                                  └──────────────────┘ │
│         │ .jtl results                                          │
│         ▼                                                        │
│  ┌──────────────┐     ┌──────────────────────────────────────┐  │
│  │  HTML Report │     │  SLA Threshold Check                 │  │
│  │  (artifact)  │     │  Error Rate < 2% | P95 < 5000ms     │  │
│  └──────────────┘     │  ❌ Fails pipeline if breached        │  │
│                        └──────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Load Generator | Apache JMeter 5.6.3 | Virtual user simulation, HTTP requests, assertions |
| Metrics Store | InfluxDB 1.8 | Time-series storage for real-time metrics streaming |
| Visualisation | Grafana 10.2 | Live dashboards: throughput, response times, error rates |
| Containerisation | Docker Compose | Reproducible monitoring stack, no manual installs |
| CI/CD | GitHub Actions | Automated test execution, SLA validation, PR feedback |
| Scripting | Bash + Python 3 | Test orchestration, JTL analysis, Markdown reporting |

---

## Repository Structure

```
jmeter-influxdb-grafana-cicd/
│
├── .github/workflows/
│   ├── performance-test.yml      ← Main pipeline (load/stress/spike, manual + scheduled)
│   └── smoke-test.yml            ← Quick sanity test on feature branch pushes
│
├── jmeter/
│   ├── test-plans/
│   │   ├── api-load-test.jmx     ← 50 VUs, 5 min sustained load (3 thread groups)
│   │   ├── api-stress-test.jmx   ← Step load: 10→50→100 VUs (breaking point)
│   │   └── api-spike-test.jmx    ← Baseline→150 VU spike→recovery test
│   ├── data/
│   │   └── test-data.csv         ← Parameterised test data (postId, userId, title, body)
│   └── plugins/
│       └── PLUGINS.md            ← Plugin installation guide
│
├── docker/
│   ├── docker-compose.yml        ← InfluxDB 1.8 + Grafana 10.2 stack
│   ├── influxdb/
│   │   └── influxdb.conf         ← InfluxDB configuration
│   └── grafana/
│       ├── provisioning/
│       │   ├── datasources/      ← Auto-configure InfluxDB datasource
│       │   └── dashboards/       ← Auto-load dashboard on startup
│       └── dashboards/
│           └── jmeter-performance.json  ← Pre-built Grafana dashboard
│
├── scripts/
│   ├── setup-monitoring.sh       ← Start/stop/restart InfluxDB + Grafana locally
│   ├── run-tests.sh              ← Run tests locally with full parameterisation
│   └── generate-report.sh       ← Generate HTML + Markdown reports from .jtl
│
├── reports/                      ← Test results (gitignored, uploaded as CI artifacts)
└── README.md
```

---

## Test Scenarios

### Load Test (`api-load-test.jmx`)

Validates steady-state performance under expected production load.

| Parameter | Default | Description |
|-----------|---------|-------------|
| VUs | 50 | Virtual users (configurable via `THREAD_COUNT`) |
| Ramp-up | 120s | Time to reach full load |
| Steady duration | 300s | Sustained load period |
| Workload mix | 50% GET / 30% POST-PUT / 20% Search | Realistic traffic distribution |

**SLA thresholds:** Error rate < 2% \| P95 < 5000ms

**API endpoints tested:**
- `GET /posts` — list all posts
- `GET /posts/{id}` — get single post (with JSON extraction for chaining)
- `GET /users/{userId}/posts` — user-scoped query
- `POST /posts` — create new resource (JSON body from CSV)
- `PUT /posts/{id}` — update resource
- `GET /posts/{id}/comments` — nested resource query

### Stress Test (`api-stress-test.jmx`)

Identifies the system's breaking point via step-load escalation.

| Step | VUs | Duration |
|------|-----|----------|
| 1 | 10 | 60s |
| 2 | 50 | 60s |
| 3 | 100 | 60s |

**Observation:** Where does P95 degrade beyond 5s? Where does error rate exceed 1%?

### Spike Test (`api-spike-test.jmx`)

Tests elasticity and recovery from sudden traffic surges.

| Phase | VUs | Duration |
|-------|-----|----------|
| Baseline | 10 | 60s |
| **Spike** | **150** | **60s** |
| Recovery | 10 | 60s |

**Observation:** Does the system recover to baseline response times post-spike?

---

## Quick Start (Local)

> ⚠️ **Local demo only.** The Docker stack runs with `INFLUXDB_HTTP_AUTH_ENABLED=false` and Grafana anonymous viewer access enabled — intentional for zero-friction local use. Do **not** expose ports 3000 or 8086 to the internet in this configuration.

### Prerequisites

- Docker Desktop (for monitoring stack)
- Apache JMeter 5.6.3 (or use the download scripts)
- Bash (macOS/Linux) or Git Bash (Windows)

### 1. Start the Monitoring Stack

```bash
./scripts/setup-monitoring.sh
```

- **Grafana:** http://localhost:3000 (admin / admin)
- **InfluxDB:** http://localhost:8086
- Dashboard auto-loads: **JMeter Performance Dashboard**

### 2. Run a Test

```bash
# Load test with defaults (50 VUs, 5 min)
./scripts/run-tests.sh --type load

# Stress test with custom VU count
./scripts/run-tests.sh --type stress --threads 100

# Spike test
./scripts/run-tests.sh --type spike

# All three tests in sequence
./scripts/run-tests.sh --type all

# Against a different target (e.g. your own API)
./scripts/run-tests.sh --type load --url api.myapp.com --protocol https --threads 25 --duration 120
```

### 3. View Results in Grafana

1. Open http://localhost:3000
2. Navigate to: **Performance Testing → JMeter Performance Dashboard**
3. Select your application from the **Application** dropdown
4. Watch metrics update in real-time during the test run

### 4. Generate an HTML Report

```bash
./scripts/generate-report.sh --jtl reports/load_20241201_143000.jtl
# HTML report opens at: reports/load_20241201_143000_html/index.html
# Markdown summary at:  reports/load_20241201_143000_html/summary.md
```

---

## CI/CD Pipeline (GitHub Actions)

### Trigger Methods

| Trigger | Behaviour |
|---------|-----------|
| `workflow_dispatch` | Manual run — choose test type, VU count, duration, URL, SLA thresholds |
| Pull Request to `main`/`develop` | Auto-runs load test at 5 VUs / 60s, posts results as PR comment |
| Schedule (`0 14 * * 1-5`) | Nightly AEST run, Monday–Friday |
| Push to `feature/**` | Smoke test (5 VUs / 60s) via `smoke-test.yml` |

### Pipeline Jobs

```
start-monitoring-stack
    │ (Docker Compose: InfluxDB + Grafana)
    ▼
setup-jmeter
    │ (Download + cache JMeter 5.6.3, install plugins)
    ▼
run-performance-tests
    │ (Matrix: load / stress / spike)
    │ (JMeter → InfluxDB real-time streaming)
    │ (HTML report generation)
    │ (SLA evaluation → fails pipeline if breached)
    ▼
comment-pr-results          cleanup
    │ (Posts Markdown         │ (docker compose down -v)
    │  table to PR)           │
    ▼                         ▼
```

### Manual Trigger (workflow_dispatch)

Navigate to **Actions → Performance Test Pipeline → Run workflow** and configure:

| Input | Default | Notes |
|-------|---------|-------|
| `test_type` | `load` | `load` \| `stress` \| `spike` \| `all` |
| `thread_count` | `50` | Virtual users |
| `duration` | `300` | Seconds |
| `ramp_up` | `120` | Seconds |
| `base_url` | `jsonplaceholder.typicode.com` | Target host (no protocol) |
| `error_rate_threshold` | `2` | % — pipeline fails if exceeded |
| `p95_threshold_ms` | `5000` | ms — pipeline fails if P95 exceeds |

### Artifacts

Test results are uploaded as GitHub Actions artifacts and retained for 30 days:

- `perf-results-load-{run_number}/` — JTL, HTML report, Markdown summary
- `perf-results-stress-{run_number}/`
- `perf-results-spike-{run_number}/`

---

## Grafana Dashboard

The pre-provisioned dashboard (`docker/grafana/dashboards/jmeter-performance.json`) includes:

| Panel | Type | Description |
|-------|------|-------------|
| Throughput (req/s) | Stat | Current request rate, colour-coded |
| Avg Response Time | Stat | Live average with green/yellow/red thresholds |
| P95 Response Time | Stat | 95th percentile response time |
| Error Rate % | Stat | Live error rate with SLA colouring |
| Active VUs | Stat | Current virtual user count |
| Total Requests | Stat | Cumulative count |
| Response Time Percentiles | Time Series | Avg, P90, P95, P99, Max over time |
| P95 SLA Gauge | Gauge | Visual threshold gauge (< 5s = green) |
| Throughput vs Error Rate | Time Series | Dual-axis: req/s + error% |
| Active VUs Over Time | Time Series | Concurrency profile |
| Transaction Breakdown | Table | Per-endpoint summary with SLA colouring |

**Variables:**
- `application` — filter by test name (auto-populated from InfluxDB)
- `interval` — auto / 10s / 30s / 1m / 5m

---

## JMeter InfluxDB Backend Listener

The tests use JMeter's **built-in** `InfluxdbBackendListenerClient` (no plugin required from JMeter 3.3+):

```xml
<BackendListener ...>
  <influxdbUrl>http://localhost:8086/write?db=jmeter</influxdbUrl>
  <application>rest-api-load-test</application>
  <measurement>jmeter</measurement>
  <percentiles>90;95;99</percentiles>
  <summaryOnly>false</summaryOnly>
  <samplersRegex>.*</samplersRegex>
</BackendListener>
```

**InfluxDB schema (measurement: `jmeter`):**

| Tag | Description |
|-----|-------------|
| `application` | Test/app name |
| `transaction` | Sampler label or `all`/`internal` |
| `statut` | `ok` or `ko` |

| Field | Description |
|-------|-------------|
| `avg`, `min`, `max` | Response time statistics |
| `pct90.0`, `pct95.0`, `pct99.0` | Percentiles |
| `count`, `failed` | Request counts |
| `maxAT`, `minAT`, `meanAT` | Active thread counts |

---

## Test Data Parameterisation

Tests are data-driven using `jmeter/data/test-data.csv`:

```
postId,userId,title,body
1,1,"sunt aut facere...","quia et suscipit..."
...
```

- CSV is loaded with `CSVDataSet` in `shareMode.all` (shared across all threads)
- Recycles when all rows are consumed — no thread will ever exhaust data
- Variables: `${postId}`, `${userId}`, `${title}`, `${body}`

---

## Assertions & Validations

Every endpoint includes layered assertions:

1. **HTTP Status Assertion** — `200 OK` or `201 Created`
2. **Duration Assertion** — per-endpoint SLA (e.g., GET < 1500ms, POST < 3000ms)
3. **Response Assertion** — validates response body contains expected field (e.g., `"id"`)
4. **Regex Extractor** — extracts values for request chaining (e.g., `"id":\s*(\d+)` → `createdPostId`)

---

## SLA Thresholds

The pipeline enforces two hard gates — the build fails if either is breached:

| Metric | Threshold | Where enforced |
|--------|-----------|----------------|
| Error Rate | < 2% | `performance-test.yml` + `generate-report.sh` |
| P95 Response Time | < 5000ms | `performance-test.yml` + `generate-report.sh` |

Smoke tests use relaxed thresholds (error rate < 5%, P95 < 10 000ms) to avoid false positives on quick sanity runs.

These values target the public [JSONPlaceholder](https://jsonplaceholder.typicode.com) API. When pointing at your own service, tune them via the `error_rate_threshold` and `p95_threshold_ms` workflow inputs, or the `--threads` / `--duration` flags locally.

---

## Adapting for Your Own API

1. **Update test plans** — change the HTTP sampler paths and assertions to match your API
2. **Update test data** — replace `jmeter/data/test-data.csv` with your domain data
3. **Set the target URL** — via `--url` flag locally or `base_url` input in CI
4. **Adjust SLA thresholds** — update `DurationAssertion` values in JMX files and CI inputs
5. **Extend the Grafana dashboard** — add panels for your specific transactions

---

## License

MIT — free to use, adapt, and extend.

---

> **Author:** Syed Sabah Hassan — Test Automation Architect
> 18+ years in performance engineering across Federal Government and Banking (Services Australia, NAB, ASB [CBA], ANZ).
> Tools: JMeter · K6 · Gatling · Grafana · InfluxDB · Docker · GitHub Actions
> sabahcomp@gmail.com
