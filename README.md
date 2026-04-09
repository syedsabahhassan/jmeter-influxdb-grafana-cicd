# JMeter + InfluxDB + Grafana — CI/CD Performance Testing Reference

[![JMeter](https://img.shields.io/badge/JMeter-5.6.3-orange?logo=apache)](https://jmeter.apache.org/)
[![InfluxDB](https://img.shields.io/badge/InfluxDB-1.8-blue)](https://www.influxdata.com/)
[![Grafana](https://img.shields.io/badge/Grafana-10.2-orange?logo=grafana)](https://grafana.com/)
[![GitHub Actions](https://img.shields.io/badge/CI-GitHub%20Actions-black?logo=github-actions)](https://github.com/features/actions)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)](https://docs.docker.com/compose/)

JMeter performance tests running inside GitHub Actions, with metrics streaming live to InfluxDB and Grafana during execution. Includes load, stress, and spike scenarios, SLA gates that fail the build, HTML reports as artifacts, and a Docker Compose monitoring stack you can start locally in one command.

The target API is [JSONPlaceholder](https://jsonplaceholder.typicode.com) — a public mock. This is a reference implementation for the tooling and wiring, not a live load-testing engagement.

---

## What this demonstrates

- Load, stress, and spike test plans written in JMeter (JMX)
- Real-time metrics streaming via JMeter's built-in InfluxDB Backend Listener
- A pre-provisioned Grafana dashboard that loads automatically on stack start
- GitHub Actions pipeline with manual trigger, PR trigger, and nightly schedule
- SLA gates that fail the pipeline when error rate or P95 response time exceed thresholds
- JMeter HTML report generated per run and uploaded as a CI artifact
- Docker Compose setup for InfluxDB + Grafana — no manual config required

---

## How it works

```
JMeter (test run)
    │
    ├── streams metrics in real time ──▶ InfluxDB 1.8 ──▶ Grafana dashboard
    │
    └── writes .jtl results file
            │
            ├── JMeter HTML report (generated post-run)
            └── Python SLA check (error rate + P95 threshold)
                    │
                    └── fails the GitHub Actions build if breached
```

---

## Repository structure

```
jmeter-influxdb-grafana-cicd/
│
├── .github/workflows/
│   ├── performance-test.yml     # main pipeline — load/stress/spike, manual + scheduled
│   └── smoke-test.yml           # lightweight sanity check on feature branch pushes
│
├── jmeter/
│   ├── test-plans/
│   │   ├── api-load-test.jmx    # 50 VUs, 5 min sustained
│   │   ├── api-stress-test.jmx  # step load: 10 → 50 → 100 VUs
│   │   └── api-spike-test.jmx   # baseline → 150 VU spike → recovery
│   └── data/
│       └── test-data.csv        # parameterised request data (postId, userId, etc.)
│
├── docker/
│   ├── docker-compose.yml       # InfluxDB 1.8 + Grafana 10.2
│   └── grafana/
│       ├── provisioning/        # auto-configured datasource + dashboard loader
│       └── dashboards/
│           └── jmeter-performance.json
│
├── scripts/
│   ├── setup-monitoring.sh      # start/stop Docker stack locally
│   ├── run-tests.sh             # run any test type locally with full options
│   └── generate-report.sh       # produce HTML + Markdown summary from a .jtl file
│
└── reports/                     # gitignored — created at runtime, uploaded as CI artifacts
```

---

## Running locally

**Prerequisites:** Docker Desktop, JMeter 5.6.3, Bash

> The Docker stack runs with auth disabled and Grafana anonymous access on — intentional for local use. Don't expose ports 3000 or 8086 publicly in this config.

```bash
# 1. Start InfluxDB + Grafana
./scripts/setup-monitoring.sh

# Grafana:  http://localhost:3000  (admin / admin)
# InfluxDB: http://localhost:8086

# 2. Run a test
./scripts/run-tests.sh --type load              # 50 VUs, 5 min, default target
./scripts/run-tests.sh --type stress
./scripts/run-tests.sh --type spike
./scripts/run-tests.sh --type all               # runs all three in sequence

# Point at your own API:
./scripts/run-tests.sh --type load --url api.myapp.com --threads 25 --duration 120

# 3. Generate an HTML report from results
./scripts/generate-report.sh --jtl reports/load_20241201_143000.jtl
```

---

## Test scenarios

| Test | VUs | Duration | Intent |
|------|-----|----------|--------|
| Load | 50 | 5 min (120s ramp) | Steady-state behaviour under expected load |
| Stress | 10 → 50 → 100 | 60s per step | Find the point where the system degrades |
| Spike | 10 → 150 → 10 | 60s each phase | Check recovery after a sudden surge |
| Smoke | 5 | 60s | Quick sanity check on feature branch pushes |

Each test plan covers six JSONPlaceholder endpoints across GET, POST, and PUT operations. Requests are parameterised from CSV and chained where relevant (extracted IDs reused in subsequent requests).

**Assertions per request:**
- HTTP status code (200 / 201)
- Response time duration (per-endpoint limit)
- Response body contains expected field

---

## CI/CD pipeline

The main workflow (`performance-test.yml`) supports three trigger modes:

| Trigger | What runs |
|---------|-----------|
| `workflow_dispatch` | Manual — pick test type, VU count, duration, target URL, SLA thresholds |
| Pull request to `main`/`develop` | Load test at 5 VUs / 60s, result posted as PR comment |
| Schedule (`0 14 * * 1-5`) | Nightly run, weekdays (AEST midnight) |

**Jobs:**

1. **Setup JMeter** — downloads and caches JMeter 5.6.3 and plugins
2. **Run tests** — starts the Docker monitoring stack, executes the selected test(s), checks SLAs, generates report, uploads artifacts
3. **Comment PR** — posts a Markdown results summary on pull requests (PR trigger only)

Artifacts are retained for 30 days: `perf-results-{type}-{run_number}/` contains the JTL file, HTML report, and a Markdown summary.

### Manual trigger inputs

Navigate to **Actions → Performance Test Pipeline → Run workflow**:

| Input | Default | Notes |
|-------|---------|-------|
| `test_type` | `load` | `load` \| `stress` \| `spike` \| `all` |
| `thread_count` | `50` | Virtual users |
| `duration` | `300` | Seconds |
| `ramp_up` | `120` | Seconds |
| `base_url` | `jsonplaceholder.typicode.com` | Target host (no protocol) |
| `error_rate_threshold` | `2` | % — build fails if exceeded |
| `p95_threshold_ms` | `5000` | ms — build fails if P95 exceeds |

---

## Monitoring and dashboards

The Grafana dashboard provisions automatically when the stack starts — no manual import.

**Panels include:** throughput (req/s), average and P95 response time, error rate, active VU count, response time percentile trends over time, per-transaction breakdown table, and a P95 SLA gauge.

Filter by test run using the `application` dropdown — it's populated from InfluxDB once a test is writing data.

Metrics are written by JMeter's built-in `InfluxdbBackendListenerClient` (available since JMeter 3.3, no extra plugin needed).

---

## SLA checks

Two pipeline gates enforced after each test run:

| Metric | Threshold |
|--------|-----------|
| Error rate | < 2% |
| P95 response time | < 5 000ms |

The build fails if either is breached. Smoke tests use looser thresholds (5% / 10 000ms) to avoid noise on short runs.

Thresholds are configurable per run via `workflow_dispatch` inputs, or locally via the scripts.

---

## Limitations

- **Target is a public mock API.** JSONPlaceholder responds consistently and never degrades, which makes it a weak load target. This repo is about the pipeline setup, not meaningful performance findings.
- **InfluxDB 1.8.** Uses v1 specifically to match JMeter's built-in Backend Listener configuration. Migrating to InfluxDB v2 would require switching to the Flux query language and updating both the listener config and the Grafana datasource.
- **Auth is disabled.** The Docker stack runs without InfluxDB auth and with Grafana anonymous viewer access — fine for local use, not appropriate for any shared environment.
- **Grafana is not visible in CI.** The monitoring stack starts inside the GitHub Actions runner. There's no persistent or external Grafana instance — dashboards only update during local runs.

---

## Adapting for your own project

1. Replace the HTTP samplers in the JMX files with your own endpoints
2. Swap `jmeter/data/test-data.csv` for data that matches your domain
3. Set `base_url` (CI) or `--url` (local scripts) to your target
4. Tune per-endpoint `DurationAssertion` values and the pipeline SLA thresholds
5. Update or replace the Grafana dashboard panels as needed

---

## Possible next steps

- Add a CI badge once the pipeline is consistently green
- Migrate InfluxDB to v2 and update queries to Flux
- Replace the duplicated inline SLA logic with a shared script
- Add distributed JMeter mode (controller + remote injectors) for genuine high-load scenarios
- Store a baseline result and compare P95 across runs

---

MIT licence — free to use and adapt.

*Syed Sabah Hassan · sabahcomp@gmail.com*
