#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REGISTRY="${DOCKER_REGISTRY:-ghcr.io}"
IMAGE_TAG="${1:-${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')}}"
PUSH="${PUSH:-false}"

SERVICES="${SERVICES:-eval/backend:docker/Dockerfile.backend eval/frontend:docker/Dockerfile.frontend eval/evaluation:docker/Dockerfile.evaluation eval/gateway:docker/Dockerfile.gateway}"

BUILD_START_TIME=$(date +%s)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

build_image() {
    local name="$1"
    local dockerfile="$2"
    local context="${PROJECT_ROOT}"
    local image_start_time

    image_start_time=$(date +%s)

    log "Building ${name} image with tag ${IMAGE_TAG}..."

    docker build \
        --file "${dockerfile}" \
        --tag "${REGISTRY}/${name}:${IMAGE_TAG}" \
        --tag "${REGISTRY}/${name}:latest" \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        "${context}"

    local image_end_time
    image_end_time=$(date +%s)
    local elapsed=$((image_end_time - image_start_time))

    log "Built ${REGISTRY}/${name}:${IMAGE_TAG} (${elapsed}s)"

    if [ "${PUSH}" = "true" ]; then
        log "Pushing ${name}..."
        docker push "${REGISTRY}/${name}:${IMAGE_TAG}"
        docker push "${REGISTRY}/${name}:latest"
        log "Pushed ${REGISTRY}/${name}:${IMAGE_TAG}"
    fi

    BUILT_IMAGES+=("${name}")
    BUILD_TIMES["${name}"]="${elapsed}"
}

BUILT_IMAGES=()
declare -A BUILD_TIMES

log "=== Build Started ==="
log "Image Tag: ${IMAGE_TAG}"
log "Registry: ${REGISTRY}"
log "Push: ${PUSH}"
log "Services: ${SERVICES}"

for service in ${SERVICES}; do
    name="${service%%:*}"
    dockerfile="${service#*:}"
    build_image "${name}" "${PROJECT_ROOT}/${dockerfile}"
done

BUILD_END_TIME=$(date +%s)
TOTAL_ELAPSED=$((BUILD_END_TIME - BUILD_START_TIME))

log "=== Build Summary ==="

echo ""
echo "==============================================="
echo "            Build Summary"
echo "==============================================="
printf "%-30s %-20s %-12s %-10s\n" "Image" "Tag" "Build Time" "Pushed"
echo "-----------------------------------------------"
for name in "${BUILT_IMAGES[@]}"; do
    push_status="no"
    if [ "${PUSH}" = "true" ]; then
        push_status="yes"
    fi
    printf "%-30s %-20s %-12s %-10s\n" "${REGISTRY}/${name}" "${IMAGE_TAG}" "${BUILD_TIMES[${name}]}s" "${push_status}"
done
echo "-----------------------------------------------"
printf "%-30s %-20s %-12s %-10s\n" "" "" "${TOTAL_ELAPSED}s" ""
echo "==============================================="

log "=== Build Completed ==="
