#!/bin/bash
# ============================================================
# 配置本地域名代理（写入 /etc/hosts + 启动 Nginx 代理容器）
# 运行一次即可，之后浏览器直接访问 http://xxx.test
# ============================================================
set -euo pipefail

HOSTS_FILE="/etc/hosts"
MARKER="local-dev-domains"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

# 1. 配置 /etc/hosts
if grep -q "$MARKER" "$HOSTS_FILE" 2>/dev/null; then
    info "/etc/hosts 已配置过，跳过"
else
    info "配置 /etc/hosts（需要管理员密码）..."
    osascript -e "do shell script \"echo '' >> $HOSTS_FILE && echo '# $MARKER' >> $HOSTS_FILE && echo '127.0.0.1 eval.test eval-answer.test eval-mcp.test eval-answer-ui.test' >> $HOSTS_FILE && echo '127.0.0.1 perm.test bizgraph.test basedata.test' >> $HOSTS_FILE && echo '127.0.0.1 portainer.test admin.test' >> $HOSTS_FILE\" with administrator privileges"
    success "/etc/hosts 已配置"
fi

# 2. 启动 Nginx 代理容器
info "启动 Nginx 代理容器..."
cd "${ROOT_DIR}"
docker compose -f docker-compose.infra.yml up -d dev-proxy

echo ""
success "==========================================="
success "  域名代理已就绪"
success "==========================================="
echo ""
info "  http://eval.test          → eval-boot (8080)"
info "  http://eval-answer.test   → eval-answer-boot (8081)"
info "  http://eval-mcp.test      → eval-mcp-server (8083)"
info "  http://eval-answer-ui.test → eval-answer-ui (8030)"
info "  http://perm.test          → perm-boot (8180)"
info "  http://bizgraph.test      → bizgraph-new (8283)"
info "  http://basedata.test      → basedata-boot (8380)"
info "  http://portainer.test     → Portainer (9000)"
info "  http://admin.test         → Admin Server (9001)"
