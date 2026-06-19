#!/bin/bash
# ============================================================
# 停止指定项目容器（基础设施保持运行）
# 用法: ./stop-app.sh <项目名>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PROFILE="${1:?Usage: $0 <eval|perm|bizgraph|basedata|all>}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

info "停止 ${PROFILE} 项目容器（基础设施保持运行）..."

# 停止并删除该 profile 的应用容器
cd "${ROOT_DIR}"
docker compose \
    -f "docker-compose.infra.yml" \
    -f "docker-compose.apps.yml" \
    --profile "${PROFILE}" \
    stop

docker compose \
    -f "docker-compose.infra.yml" \
    -f "docker-compose.apps.yml" \
    --profile "${PROFILE}" \
    rm -f

success "${PROFILE} 项目容器已停止"
info "基础设施仍在运行，停止全部请用: ./stop-all.sh"
