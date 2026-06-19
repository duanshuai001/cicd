#!/bin/bash
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

# 项目名到服务名映射（用 case 而非 declare -A，兼容 bash 3.2.57）
get_services_for_project() {
  case "$1" in
    eval)    echo "eval-boot eval-answer-boot eval-mcp-server eval-answer-ui" ;;
    perm)    echo "perm-boot" ;;
    bizgraph) echo "bizgraph-new" ;;
    basedata) echo "basedata-boot" ;;
    *)       echo "" ;;
  esac
}

get_profile_for_service() {
  for proj in eval perm bizgraph basedata; do
    if echo " $(get_services_for_project "$proj") " | grep -q " $1 "; then
      echo "$proj"
      return
    fi
  done
  echo ""
}

# 判断是项目名还是服务名
SERVICES="$(get_services_for_project "$TARGET")"
if [ -n "$SERVICES" ]; then
    # 是项目名，重建该项目下所有服务
    PROFILE="$TARGET"
    info "重建 ${TARGET} 项目所有服务: ${SERVICES}"
else
    # 是服务名，需要找到对应的 profile
    SERVICES="$TARGET"
    PROFILE="$(get_profile_for_service "$TARGET")"
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
