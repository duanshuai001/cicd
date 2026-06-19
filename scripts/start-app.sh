#!/bin/bash
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

# eval 项目需要先本地构建 jar
if echo " eval all " | grep -q " $PROFILE "; then
    EVAL_DIR="${ROOT_DIR}/eval_new"
    if [ ! -f "${EVAL_DIR}/eval-boot/target/eval-boot-1.0.0-SNAPSHOT.jar" ]; then
        info "Eval 项目尚未构建 jar，正在执行 mvn package..."
        cd "${EVAL_DIR}"
        mvn package -DskipTests -q
        success "Eval jar 构建完成"
    fi
fi

info "启动基础设施 + ${PROFILE} 项目容器..."
cd "${ROOT_DIR}"
docker compose \
    -f "docker-compose.infra.yml" \
    -f "docker-compose.apps.yml" \
    --profile "${PROFILE}" \
    up -d --build

echo ""
success "==========================================="
success "  ${PROFILE} 项目已启动（全栈模式）"
success "==========================================="
echo ""
info "  域名访问："
if echo " eval all " | grep -q " $PROFILE "; then
info "    http://eval.test          → eval-boot"
info "    http://eval-answer.test   → eval-answer-boot"
info "    http://eval-mcp.test      → eval-mcp-server"
info "    http://eval-answer-ui.test → eval-answer-ui"
fi
if echo " perm all " | grep -q " $PROFILE "; then
info "    http://perm.test          → perm-boot"
fi
if echo " bizgraph all " | grep -q " $PROFILE "; then
info "    http://bizgraph.test      → bizgraph-new"
fi
if echo " basedata all " | grep -q " $PROFILE "; then
info "    http://basedata.test      → basedata-boot"
fi
echo ""
info "  查看状态：./status.sh"
info "  重建服务：./rebuild.sh <服务名>"
info "  停止项目：./stop-app.sh ${PROFILE}"
