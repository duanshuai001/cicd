#!/bin/bash
# ============================================================
# 停止全部容器（包括基础设施）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

info "停止全部容器..."
cd "${ROOT_DIR}"
docker compose \
    -f "docker-compose.infra.yml" \
    -f "docker-compose.apps.yml" \
    --profile all \
    down

success "全部容器已停止"
