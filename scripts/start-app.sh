#!/usr/bin/env bash
# ============================================================
# 全栈模式：启动基础设施 + 指定项目容器
# 用法: ./start-app.sh <项目名>
#   项目名: eval / perm / bizgraph / basedata / all
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PROFILE="${1:?Usage: $0 <eval|perm|bizgraph|basedata|all>}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# 验证 profile
VALID_PROFILES="eval perm bizgraph basedata all"
if ! echo " $VALID_PROFILES " | grep -q " $PROFILE "; then
    error "无效的项目名: $PROFILE"
    echo "  可选: $VALID_PROFILES"
    exit 1
fi

info "启动基础设施 + ${PROFILE} 项目容器..."
docker compose \
    -f "${ROOT_DIR}/docker-compose.infra.yml" \
    -f "${ROOT_DIR}/docker-compose.apps.yml" \
    --profile "${PROFILE}" \
    up -d

echo ""
success "==========================================="
success "  ${PROFILE} 项目已启动（全栈模式）"
success "==========================================="
echo ""
info "  Portainer:   http://localhost:9000"
info "  查看状态：./status.sh"
info "  重建服务：./rebuild.sh <服务名>"
info "  停止项目：./stop-app.sh ${PROFILE}"
