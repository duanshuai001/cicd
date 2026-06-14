#!/usr/bin/env bash
# ============================================================
# 查看所有服务状态
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }

echo ""
info "==========================================="
info "  服务状态一览"
info "==========================================="
echo ""

# 基础设施状态
info "--- 基础设施 ---"
for container in dev-postgres dev-redis dev-zookeeper dev-portainer; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        port=$(docker ps --format "{{.Names}}\t{{.Ports}}" | grep "^${container}" | awk '{print $2}' | head -1)
        echo -e "  ${GREEN}●${NC} ${container}  ${port}"
    else
        echo -e "  ○ ${container}  (stopped)"
    fi
done

echo ""

# 应用状态 - Eval
info "--- Eval（80xx）---"
for container in eval-boot eval-answer-boot eval-mcp-server eval-answer-ui; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        port=$(docker ps --format "{{.Names}}\t{{.Ports}}" | grep "^${container}" | awk '{print $2}' | head -1)
        echo -e "  ${GREEN}●${NC} ${container}  ${port}"
    else
        echo -e "  ○ ${container}  (stopped)"
    fi
done

echo ""

# 应用状态 - Perm
info "--- Perm（81xx）---"
for container in perm-boot; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        port=$(docker ps --format "{{.Names}}\t{{.Ports}}" | grep "^${container}" | awk '{print $2}' | head -1)
        echo -e "  ${GREEN}●${NC} ${container}  ${port}"
    else
        echo -e "  ○ ${container}  (stopped)"
    fi
done

echo ""

# 应用状态 - BizGraph
info "--- BizGraph（82xx）---"
for container in bizgraph-backend bizgraph-frontend bizgraph-mcp; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        port=$(docker ps --format "{{.Names}}\t{{.Ports}}" | grep "^${container}" | awk '{print $2}' | head -1)
        echo -e "  ${GREEN}●${NC} ${container}  ${port}"
    else
        echo -e "  ○ ${container}  (stopped)"
    fi
done

echo ""

# 应用状态 - Basedata
info "--- Basedata（83xx）---"
for container in basedata-boot; do
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        port=$(docker ps --format "{{.Names}}\t{{.Ports}}" | grep "^${container}" | awk '{print $2}' | head -1)
        echo -e "  ${GREEN}●${NC} ${container}  ${port}"
    else
        echo -e "  ○ ${container}  (stopped)"
    fi
done

echo ""
info "Portainer: http://localhost:9000"
