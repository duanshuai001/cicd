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
docker compose -f "${ROOT_DIR}/docker-compose.infra.yml" up -d

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
info "  ZooKeeper:  localhost:2181"
info "  Portainer:   http://localhost:9000"
echo ""
info "  下一步：在 IDE 中启动应用，profile=local"
info "  停止：docker compose -f ${ROOT_DIR}/docker-compose.infra.yml down"
