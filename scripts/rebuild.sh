#!/usr/bin/env bash
# ============================================================
# 重新构建+重启指定服务（加载最新代码）
# 用法:
#   ./rebuild.sh eval-boot          # 重建单个服务
#   ./rebuild.sh eval               # 重建整个项目
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TARGET="${1:?Usage: $0 <服务名|项目名>}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

COMPOSE_FILES="-f docker-compose.infra.yml -f docker-compose.apps.yml"

# 项目名到服务名映射
declare -A PROJECT_SERVICES
PROJECT_SERVICES[eval]="eval-boot eval-answer-boot eval-mcp-server eval-answer-ui"
PROJECT_SERVICES[perm]="perm-boot"
PROJECT_SERVICES[bizgraph]="bizgraph-backend bizgraph-frontend bizgraph-mcp"
PROJECT_SERVICES[basedata]="basedata-boot"

# 判断是项目名还是服务名
if [ -n "${PROJECT_SERVICES[$TARGET]+x}" ]; then
    # 是项目名，重建该项目下所有服务
    SERVICES="${PROJECT_SERVICES[$TARGET]}"
    PROFILE="$TARGET"
    info "重建 ${TARGET} 项目所有服务: ${SERVICES}"
else
    # 是服务名，需要找到对应的 profile
    SERVICES="$TARGET"
    PROFILE=""
    for proj in "${!PROJECT_SERVICES[@]}"; do
        if echo " ${PROJECT_SERVICES[$proj]} " | grep -q " $TARGET "; then
            PROFILE="$proj"
            break
        fi
    done
    if [ -z "$PROFILE" ]; then
        warn "未找到服务 ${TARGET} 对应的项目，使用 all profile"
        PROFILE="all"
    fi
    info "重建服务: ${TARGET} (profile: ${PROFILE})"
fi

# 重新构建并重启
cd "${ROOT_DIR}"
for svc in ${SERVICES}; do
    info "重新构建 ${svc}..."
    docker compose ${COMPOSE_FILES} --profile "${PROFILE}" up -d --build "${svc}"
    success "${svc} 重建完成"
done

echo ""
success "==========================================="
success "  重建完成"
success "==========================================="
info "  查看状态：./status.sh"
info "  查看日志：docker compose ${COMPOSE_FILES} logs -f ${SERVICES%% *}"
