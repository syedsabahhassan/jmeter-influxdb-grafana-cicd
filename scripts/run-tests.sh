#!/usr/bin/env bash
# =============================================================================
# run-tests.sh
# Runs JMeter performance tests locally against the monitoring stack.
# Author: Syed Sabah Hassan | Senior Performance Tester
#
# Usage:
#   ./scripts/run-tests.sh --type load
#   ./scripts/run-tests.sh --type stress --threads 100
#   ./scripts/run-tests.sh --type spike
#   ./scripts/run-tests.sh --type all --url myapi.example.com
#
# Options:
#   --type       load | stress | spike | all  (default: load)
#   --threads    Number of virtual users      (default: 50)
#   --duration   Test duration in seconds     (default: 300)
#   --ramp       Ramp-up time in seconds      (default: 120)
#   --url        Target API host              (default: jsonplaceholder.typicode.com)
#   --protocol   http | https                 (default: https)
#   --jmeter     Path to JMeter home          (default: auto-detect)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]  $*${NC}"; }
log_success() { echo -e "${GREEN}[PASS]  $*${NC}"; }
log_error()   { echo -e "${RED}[FAIL]  $*${NC}"; }
log_banner()  { echo -e "${YELLOW}$*${NC}"; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
TEST_TYPE="load"
THREAD_COUNT="50"
DURATION="300"
RAMP_UP="120"
BASE_URL="jsonplaceholder.typicode.com"
PROTOCOL="https"
JMETER_HOME="${JMETER_HOME:-}"
INFLUXDB_HOST="localhost"
INFLUXDB_PORT="8086"
RESULTS_DIR="$PROJECT_ROOT/reports"
DATA_DIR="$PROJECT_ROOT/jmeter/data"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)     TEST_TYPE="$2";     shift 2 ;;
        --threads)  THREAD_COUNT="$2";  shift 2 ;;
        --duration) DURATION="$2";      shift 2 ;;
        --ramp)     RAMP_UP="$2";       shift 2 ;;
        --url)      BASE_URL="$2";      shift 2 ;;
        --protocol) PROTOCOL="$2";      shift 2 ;;
        --jmeter)   JMETER_HOME="$2";  shift 2 ;;
        -h|--help)
            sed -n '/^# Usage/,/^# Options/p' "$0"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Auto-detect JMeter
# ---------------------------------------------------------------------------
find_jmeter() {
    if [ -n "$JMETER_HOME" ] && [ -f "$JMETER_HOME/bin/jmeter" ]; then
        echo "$JMETER_HOME/bin/jmeter"
        return
    fi

    # Common install locations
    for path in \
        "/opt/apache-jmeter/bin/jmeter" \
        "/usr/local/apache-jmeter/bin/jmeter" \
        "$HOME/apache-jmeter/bin/jmeter" \
        "$PROJECT_ROOT/apache-jmeter-5.6.3/bin/jmeter"; do
        if [ -f "$path" ]; then
            echo "$path"
            return
        fi
    done

    # Fall back to PATH
    if command -v jmeter &>/dev/null; then
        echo "jmeter"
        return
    fi

    log_error "JMeter not found. Set JMETER_HOME or use --jmeter /path/to/jmeter"
    exit 1
}

JMETER_BIN=$(find_jmeter)
log_info "Using JMeter: $JMETER_BIN"

# ---------------------------------------------------------------------------
# Check monitoring stack
# ---------------------------------------------------------------------------
if ! curl -sf http://$INFLUXDB_HOST:$INFLUXDB_PORT/ping &>/dev/null; then
    log_error "InfluxDB is not running at http://$INFLUXDB_HOST:$INFLUXDB_PORT"
    echo "       Start it with: ./scripts/setup-monitoring.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Run a single test
# ---------------------------------------------------------------------------
run_test() {
    local test_type="$1"
    local jmx_file app_name jtl_file html_dir log_file

    case "$test_type" in
        load)   jmx_file="$PROJECT_ROOT/jmeter/test-plans/api-load-test.jmx"   ;;
        stress) jmx_file="$PROJECT_ROOT/jmeter/test-plans/api-stress-test.jmx" ;;
        spike)  jmx_file="$PROJECT_ROOT/jmeter/test-plans/api-spike-test.jmx"  ;;
        *)      log_error "Unknown test type: $test_type"; exit 1 ;;
    esac

    app_name="rest-api-${test_type}-test"
    jtl_file="$RESULTS_DIR/${test_type}_${TIMESTAMP}.jtl"
    html_dir="$RESULTS_DIR/${test_type}_${TIMESTAMP}_html"
    log_file="$RESULTS_DIR/${test_type}_${TIMESTAMP}_jmeter.log"

    mkdir -p "$RESULTS_DIR"

    log_banner "============================================"
    log_banner "  Running: $test_type test"
    log_banner "  Target:  $PROTOCOL://$BASE_URL"
    log_banner "  VUs:     $THREAD_COUNT"
    log_banner "  Duration: ${DURATION}s | Ramp: ${RAMP_UP}s"
    log_banner "  Metrics: http://$INFLUXDB_HOST:$INFLUXDB_PORT (app=$app_name)"
    log_banner "============================================"

    "$JMETER_BIN" \
        -n \
        -t "$jmx_file" \
        -l "$jtl_file" \
        -j "$log_file" \
        -JBASE_URL="$BASE_URL" \
        -JPROTOCOL="$PROTOCOL" \
        -JTHREAD_COUNT="$THREAD_COUNT" \
        -JDURATION="$DURATION" \
        -JRAMP_UP="$RAMP_UP" \
        -JINFLUXDB_HOST="$INFLUXDB_HOST" \
        -JINFLUXDB_PORT="$INFLUXDB_PORT" \
        -JAPP_NAME="$app_name" \
        -JDATA_DIR="$DATA_DIR" \
        -e \
        -o "$html_dir"

    log_success "Test completed: $test_type"
    log_info "JTL results:  $jtl_file"
    log_info "HTML report:  $html_dir/index.html"
    log_info "JMeter log:   $log_file"
    echo ""
    log_info "Open Grafana: http://localhost:3000 → JMeter Performance Dashboard"
    log_info "Select application: $app_name"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ "$TEST_TYPE" = "all" ]; then
    for t in load stress spike; do
        run_test "$t"
        echo ""
    done
else
    run_test "$TEST_TYPE"
fi

log_success "All done! Check reports in: $RESULTS_DIR"
