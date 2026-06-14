#!/usr/bin/env bash
# ============================================================
# 开发模式：只启动基础设施（PG/Redis/ZooKeeper/Portainer）
# 应用在 IDE 中启动，profile=local
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

info "启动基础设施（开发模式）..."
cd "${ROOT_DIR}"
docker compose -f "docker-compose.infra.yml" up -d

# 等待 PostgreSQL 就绪
info "等待 PostgreSQL 就绪..."
max_retries=30
for i in $(seq 1 $max_retries); do
    if docker exec dev-postgres pg_isready -U dev > /dev/null 2>&1; then
        success "PostgreSQL 已就绪"
        break
    fi
    if [ "$i" -eq "$max_retries" ]; then
        echo "PostgreSQL 启动超时"
        exit 1
    fi
    sleep 1
done

# 等待 ZooKeeper 就绪
info "等待 ZooKeeper 就绪..."
for i in $(seq 1 $max_retries); do
    if docker exec dev-zookeeper bash -c "echo ruok | nc localhost 2181" 2>/dev/null | grep -q "imok"; then
        success "ZooKeeper 已就绪"
        break
    fi
    if [ "$i" -eq "$max_retries" ]; then
        echo "ZooKeeper 启动超时"
        exit 1
    fi
    sleep 1
done

echo ""
success "==========================================="
success "  基础设施已就绪（开发模式）"
success "==========================================="
echo ""
info "  PostgreSQL:  localhost:5432 (dev/dev)"
info "  Redis:       localhost:6379"
info "  ZooKeeper:   localhost:2181"
info "  Portainer:   http://localhost:9000"
echo ""
success "  IDE 启动指引（profile = local）："
echo ""
info "  ┌─ Eval（数据库: eval）─────────────"
info "  │  eval-boot         → com.eval.EvalApplication"
info "  │  eval-answer-boot  → com.eval.AnswerApplication"
info "  │  eval-mcp-server   → com.eval.mcp.McpServerApplication"
info "  └─ 端口: 8080 / 8081 / 8083"
echo ""
info "  ┌─ Perm（数据库: perm, 需 Redis）──"
info "  │  perm-boot         → com.perm.boot.PermBootApplication"
info "  └─ 端口: 8081"
echo ""
info "  ┌─ BizGraph（数据库: bizgraph）─────"
info "  │  bizgraph-backend  → com.bizgraph.BizGraphApplication"
info "  │  bizgraph-mcp      → mcp 主类（查看 bizgraph-mcp 源码）"
info "  └─ 端口: 8080 / 8090"
echo ""
info "  ┌─ Basedata（数据库: basedata, 需 Redis）──"
info "  │  basedata-boot     → com.basedata.boot.BaseDataBootApplication"
info "  └─ 端口: 8083"
echo ""
info "  停止：./stop-all.sh"
