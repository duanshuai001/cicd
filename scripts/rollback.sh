#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment> [namespace]}"
NAMESPACE="${2:-${DEPLOY_NAMESPACE:-default}}"
APP_NAME="${APP_NAME:-eval}"
APP_LABEL="${APP_LABEL:-app.kubernetes.io/part-of}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== Rollback Started ==="
log "Environment: ${ENVIRONMENT}"
log "Namespace: ${NAMESPACE}"
log "App Name: ${APP_NAME}"

DEPLOYMENTS=$(kubectl get deployments -n "${NAMESPACE}" -l "${APP_LABEL}=${APP_NAME},environment="${ENVIRONMENT}"" -o jsonpath='{.items[*].metadata.name}')

if [ -z "${DEPLOYMENTS}" ]; then
    log "No deployments found for app '${APP_NAME}' in environment '${ENVIRONMENT}' namespace '${NAMESPACE}'"
    exit 1
fi

for deployment in ${DEPLOYMENTS}; do
    log "Rolling back ${deployment}..."

    REVISION_COUNT=$(kubectl rollout history deployment/"${deployment}" -n "${NAMESPACE}" -o jsonpath='{.metadata.generation}' 2>/dev/null || echo "0")

    if [ "${REVISION_COUNT}" -le 1 ]; then
        log "No previous revision available for ${deployment}, skipping"
        continue
    fi

    kubectl rollout undo deployment/"${deployment}" -n "${NAMESPACE}"
    log "Rollback initiated for ${deployment}"
done

log "Waiting for rollback to complete..."
for deployment in ${DEPLOYMENTS}; do
    kubectl rollout status deployment/"${deployment}" -n "${NAMESPACE}" --timeout=180s 2>/dev/null || true
done

log "Verifying rollback..."
kubectl get pods -n "${NAMESPACE}" -l "${APP_LABEL}=${APP_NAME},environment="${ENVIRONMENT}""

log "=== Rollback Completed ==="
