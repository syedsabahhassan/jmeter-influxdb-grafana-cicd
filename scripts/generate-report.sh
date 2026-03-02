#!/usr/bin/env bash
# =============================================================================
# generate-report.sh
# Generates an HTML report from a JMeter .jtl results file.
# Also exports key metrics as a Markdown summary (for CI PR comments).
# Author: Syed Sabah Hassan | Senior Performance Tester
#
# Usage:
#   ./scripts/generate-report.sh --jtl reports/load_results.jtl
#   ./scripts/generate-report.sh --jtl reports/load.jtl --out reports/html
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]  $*${NC}"; }
log_success() { echo -e "${GREEN}[PASS]  $*${NC}"; }
log_error()   { echo -e "${RED}[FAIL]  $*${NC}"; }

JTL_FILE=""
OUTPUT_DIR=""
JMETER_HOME="${JMETER_HOME:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jtl)    JTL_FILE="$2";   shift 2 ;;
        --out)    OUTPUT_DIR="$2"; shift 2 ;;
        --jmeter) JMETER_HOME="$2"; shift 2 ;;
        *)        log_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$JTL_FILE" ]; then
    log_error "Usage: $0 --jtl <results.jtl> [--out <output_dir>]"
    exit 1
fi

if [ ! -f "$JTL_FILE" ]; then
    log_error "JTL file not found: $JTL_FILE"
    exit 1
fi

if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="${JTL_FILE%.jtl}_html"
fi

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Generate JMeter HTML Dashboard Report
# ---------------------------------------------------------------------------
find_jmeter() {
    for path in "$JMETER_HOME/bin/jmeter" "/opt/apache-jmeter/bin/jmeter" \
                "$HOME/apache-jmeter/bin/jmeter" "$PROJECT_ROOT/apache-jmeter-5.6.3/bin/jmeter"; do
        [ -f "$path" ] && { echo "$path"; return; }
    done
    command -v jmeter 2>/dev/null || { log_error "JMeter not found."; exit 1; }
}

JMETER_BIN=$(find_jmeter)

log_info "Generating HTML report from: $JTL_FILE"
log_info "Output directory: $OUTPUT_DIR"

"$JMETER_BIN" \
    -g "$JTL_FILE" \
    -o "$OUTPUT_DIR" \
    2>/dev/null || true

log_success "HTML report generated: $OUTPUT_DIR/index.html"

# ---------------------------------------------------------------------------
# Generate Markdown summary
# ---------------------------------------------------------------------------
SUMMARY_MD="${OUTPUT_DIR}/summary.md"

python3 << PYEOF
import csv, sys, os, json
from datetime import datetime

jtl_file = "$JTL_FILE"
summary_file = "$SUMMARY_MD"

total = 0
errors = 0
response_times = []
transactions = {}
start_ms = None
end_ms = None

with open(jtl_file, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        ts = int(row.get('timeStamp', 0))
        elapsed = int(row.get('elapsed', 0))
        label = row.get('label', 'unknown')
        success = row.get('success', 'true').lower() == 'true'

        if start_ms is None or ts < start_ms:
            start_ms = ts
        end_ms_candidate = ts + elapsed
        if end_ms is None or end_ms_candidate > end_ms:
            end_ms = end_ms_candidate

        total += 1
        if not success:
            errors += 1
        response_times.append(elapsed)

        if label not in transactions:
            transactions[label] = {'count': 0, 'errors': 0, 'rts': []}
        transactions[label]['count'] += 1
        if not success:
            transactions[label]['errors'] += 1
        transactions[label]['rts'].append(elapsed)

if total == 0:
    print("No samples found in JTL")
    sys.exit(0)

response_times.sort()

def pct(data, p):
    if not data: return 0
    return data[min(int(len(data) * p / 100), len(data) - 1)]

error_rate = errors / total * 100
avg_rt = sum(response_times) / len(response_times)
p90 = pct(response_times, 90)
p95 = pct(response_times, 95)
p99 = pct(response_times, 99)
max_rt = max(response_times)
min_rt = min(response_times)
duration_s = ((end_ms or 0) - (start_ms or 0)) / 1000
throughput = total / duration_s if duration_s > 0 else 0

timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

sla_error = '✅ PASS' if error_rate < 2 else '❌ FAIL'
sla_p95   = '✅ PASS' if p95 < 5000 else '❌ FAIL'

md = f"""# Performance Test Report
**Generated:** {timestamp}
**Source file:** {jtl_file}

## Summary

| Metric | Value | SLA |
|--------|-------|-----|
| Total Requests | {total:,} | - |
| Errors | {errors:,} | - |
| Error Rate | {error_rate:.2f}% | {sla_error} (< 2%) |
| Throughput | {throughput:.2f} req/s | - |
| Avg Response Time | {avg_rt:.0f}ms | - |
| Min Response Time | {min_rt}ms | - |
| P90 Response Time | {p90}ms | - |
| P95 Response Time | {p95}ms | {sla_p95} (< 5000ms) |
| P99 Response Time | {p99}ms | - |
| Max Response Time | {max_rt}ms | - |
| Test Duration | {duration_s:.1f}s | - |

## Transaction Breakdown

| Transaction | Requests | Errors | Error% | Avg (ms) | P95 (ms) | P99 (ms) |
|-------------|----------|--------|--------|----------|----------|----------|
"""

for label, data in sorted(transactions.items()):
    if label in ('all', 'internal'):
        continue
    data['rts'].sort()
    t_avg = sum(data['rts']) / len(data['rts']) if data['rts'] else 0
    t_p95 = pct(data['rts'], 95)
    t_p99 = pct(data['rts'], 99)
    t_err_pct = data['errors'] / data['count'] * 100 if data['count'] > 0 else 0
    md += f"| {label} | {data['count']:,} | {data['errors']:,} | {t_err_pct:.1f}% | {t_avg:.0f} | {t_p95} | {t_p99} |\n"

overall = '✅ PASSED' if (error_rate < 2 and p95 < 5000) else '❌ FAILED'
md += f"""
## Overall Result: {overall}
"""

with open(summary_file, 'w') as f:
    f.write(md)

print(md)
print(f"Summary written to: {summary_file}")
PYEOF

log_success "Markdown summary: $SUMMARY_MD"
