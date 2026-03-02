#!/usr/bin/env bash
# =============================================================================
# setup-monitoring.sh
# Starts the InfluxDB + Grafana monitoring stack for local development.
# Author: Syed Sabah Hassan | Senior Performance Tester
#
# Usage:
#   ./scripts/setup-monitoring.sh           # Start stack
#   ./scripts/setup-monitoring.sh stop      # Stop stack
#   ./scripts/setup-monitoring.sh restart   # Restart stack
#   ./scripts/setup-monitoring.sh status    # Show stack status
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker/docker-compose.yml"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

log_info()    { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_success() { echo -e "${GREEN}✅ $*${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error()   { echo -e "${RED}❌ $*${NC}"; }

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
check_prerequisites() {
    log_info "Checking prerequisites..."
    for cmd in docker curl; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "$cmd is required but not installed."
            exit 1
        fi
    done

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running. Please start Docker Desktop."
        exit 1
    fi

    log_success "Prerequisites satisfied"
}

# ---------------------------------------------------------------------------
# Start monitoring stack
# ---------------------------------------------------------------------------
start_stack() {
    log_info "Starting performance monitoring stack..."
    cd "$PROJECT_ROOT/docker"

    docker compose up -d

    log_info "Waiting for InfluxDB to be healthy..."
    local retries=0
    until curl -sf http://localhost:8086/ping &>/dev/null || [ "$retries" -ge 30 ]; do
        sleep 3
        retries=$((retries + 1))
        echo -n "."
    done
    echo ""

    if curl -sf http://localhost:8086/ping &>/dev/null; then
        log_success "InfluxDB is healthy"
    else
        log_error "InfluxDB failed to start in time. Check: docker compose logs influxdb"
        exit 1
    fi

    log_info "Waiting for Grafana to be healthy..."
    retries=0
    until curl -sf http://localhost:3000/api/health &>/dev/null || [ "$retries" -ge 30 ]; do
        sleep 3
        retries=$((retries + 1))
        echo -n "."
    done
    echo ""

    if curl -sf http://localhost:3000/api/health &>/dev/null; then
        log_success "Grafana is healthy"
    else
        log_error "Grafana failed to start in time. Check: docker compose logs grafana"
        exit 1
    fi

    # Ensure jmeter database exists
    curl -sf -XPOST "http://localhost:8086/query" \
        --data-urlencode "q=CREATE DATABASE jmeter" >/dev/null 2>&1 || true
    log_success "InfluxDB 'jmeter' database ready"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Monitoring Stack is Ready!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "  ${YELLOW}Grafana:  ${NC}http://localhost:3000"
    echo -e "  ${YELLOW}          ${NC}Username: admin | Password: admin"
    echo -e "  ${YELLOW}InfluxDB: ${NC}http://localhost:8086"
    echo -e "  ${YELLOW}Database: ${NC}jmeter"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    log_info "Dashboard auto-loaded: 'JMeter Performance Dashboard'"
    log_info "Run tests and metrics will appear in real-time."
}

# ---------------------------------------------------------------------------
# Stop monitoring stack
# ---------------------------------------------------------------------------
stop_stack() {
    log_info "Stopping performance monitoring stack..."
    cd "$PROJECT_ROOT/docker"
    docker compose down
    log_success "Stack stopped (data volumes preserved)"
    log_info "To remove data volumes as well: docker compose down -v"
}

# ---------------------------------------------------------------------------
# Show stack status
# ---------------------------------------------------------------------------
show_status() {
    echo ""
    echo -e "${BLUE}=== Monitoring Stack Status ===${NC}"
    cd "$PROJECT_ROOT/docker"
    docker compose ps
    echo ""

    if curl -sf http://localhost:8086/ping &>/dev/null; then
        log_success "InfluxDB: http://localhost:8086 - HEALTHY"
    else
        log_warning "InfluxDB: http://localhost:8086 - NOT RUNNING"
    fi

    if curl -sf http://localhost:3000/api/health &>/dev/null; then
        log_success "Grafana: http://localhost:3000 - HEALTHY"
    else
        log_warning "Grafana: http://localhost:3000 - NOT RUNNING"
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
ACTION="${1:-start}"

check_prerequisites

case "$ACTION" in
    start)   start_stack ;;
    stop)    stop_stack ;;
    restart) stop_stack; start_stack ;;
    status)  show_status ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
