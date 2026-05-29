#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment> [namespace]}"
NAMESPACE="${2:-${DEPLOY_NAMESPACE:-default}}"
APP_NAME="${APP_NAME:-eval}"
APP_LABEL="${APP_LABEL:-app.kubernetes.io/part-of}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== Health Check Started ==="
log "Environment: ${ENVIRONMENT}"
log "Namespace: ${NAMESPACE}"
log "App Name: ${APP_NAME}"

check_pods() {
    log "Checking pod health..."
    local unhealthy
    unhealthy=$(kubectl get pods -n "${NAMESPACE}" -l "${APP_LABEL}=${APP_NAME},environment="${ENVIRONMENT}"" \
        --field-selector=status.phase!=Running -o name 2>/dev/null || true)

    if [ -n "${unhealthy}" ]; then
        log "Unhealthy pods found:"
        echo "${unhealthy}"
        return 1
    fi

    local crash_loop
    crash_loop=$(kubectl get pods -n "${NAMESPACE}" -l "${APP_LABEL}=${APP_NAME},environment="${ENVIRONMENT}"" \
        -o json | grep -c '"reason":"CrashLoopBackOff"' 2>/dev/null || echo "0")

    if [ "${crash_loop}" -gt 0 ]; then
        log "Found ${crash_loop} pods in CrashLoopBackOff"
        return 1
    fi

    log "All pods are running"
    return 0
}

check_readiness() {
    log "Checking readiness probes..."
    local not_ready
    not_ready=$(kubectl get pods -n "${NAMESPACE}" -l "${APP_LABEL}=${APP_NAME},environment="${ENVIRONMENT}"" \
        -o jsonpath='{.items[?(@.status.containerStatuses[0].ready!=true)].metadata.name}' 2>/dev/null || true)

    if [ -n "${not_ready}" ]; then
        log "Pods not ready:"
        echo "${not_ready}"
        return 1
    fi

    log "All pods are ready"
    return 0
}

check_endpoints() {
    log "Checking service endpoints..."

    local services
    services=$(kubectl get services -n "${NAMESPACE}" -l "${APP_LABEL}=${APP_NAME},environment="${ENVIRONMENT}"" \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

    for svc in ${services}; do
        local endpoints
        endpoints=$(kubectl get endpoints "${svc}" -n "${NAMESPACE}" \
            -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null || true)

        if [ -z "${endpoints}" ]; then
            log "Warning: No endpoints for service ${svc}"
        else
            log "Service ${svc}: endpoints OK"
        fi
    done
}

check_pods
check_readiness
check_endpoints

log "=== Health Check Completed ==="
