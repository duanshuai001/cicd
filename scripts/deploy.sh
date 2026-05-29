#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENVIRONMENT="${1:?Usage: $0 <environment> [image-tag] [namespace] [overlay-dir]}"
IMAGE_TAG="${2:-${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')}}"
NAMESPACE="${3:-${DEPLOY_NAMESPACE:-default}}"
OVERLAY_DIR="${4:-${SCRIPT_DIR}/../k8s/overlays/${ENVIRONMENT}}"
APP_LABEL="${APP_LABEL:-app.kubernetes.io/part-of}"

if [ ! -d "${OVERLAY_DIR}" ]; then
    echo "Error: Overlay directory not found for environment '${ENVIRONMENT}'"
    echo "Searched: ${OVERLAY_DIR}"
    exit 1
fi

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

MANIFEST_FILE="/tmp/deploy-k8s-manifests-${ENVIRONMENT}.yaml"

log "=== Deploy Started ==="
log "Environment: ${ENVIRONMENT}"
log "Image Tag: ${IMAGE_TAG}"
log "Namespace: ${NAMESPACE}"
log "Overlay Dir: ${OVERLAY_DIR}"

log "Building Kustomize manifests..."
kustomize build "${OVERLAY_DIR}" > "${MANIFEST_FILE}"
log "Manifests built successfully"

log "Applying manifests..."
kubectl apply -f "${MANIFEST_FILE}" --namespace="${NAMESPACE}"

log "Waiting for rollout..."
kubectl rollout status deployment -n "${NAMESPACE}" -l "${APP_LABEL}=${APP_NAME:-}" --timeout=300s

log "Verifying deployment..."
kubectl get pods -n "${NAMESPACE}" -l "${APP_LABEL}=${APP_NAME:-}"
kubectl get services -n "${NAMESPACE}"

rm -f "${MANIFEST_FILE}"

log "=== Deploy Completed ==="
