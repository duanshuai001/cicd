#!/bin/bash
# ============================================================
# 清除 macOS xattr + mvn clean + 重启所有本地服务
# 必须在 Mac 系统终端执行（非 TRAE 终端）
# 用法: ./fix-and-start-all.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# 检查是否在 TRAE 终端中运行
if [ -n "${TRAE_SOLO_CN:-}" ] || echo "$0" | grep -q "trae"; then
  error "请在 Mac 系统终端执行此脚本，不要在 TRAE 终端中运行"
  exit 1
fi

# 1. 杀掉所有已运行的 Java 进程（在应用端口上的）
info "停止现有服务..."
for port in 8080 8081 8082 8180 8283 8380; do
  pid=$(lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)
  if [ -n "$pid" ]; then
    kill $pid 2>/dev/null || true
    warn "已停止端口 $port 上的进程 (PID: $pid)"
  fi
done
sleep 2

# 2. 对每个项目做 mvn clean + xattr 清除
info "mvn clean + 清除 macOS xattr..."
for dir in \
  "${ROOT_DIR}/eval_new/eval-boot" \
  "${ROOT_DIR}/eval_new/eval-answer-boot" \
  "${ROOT_DIR}/eval_new/eval-mcp-server" \
  "${ROOT_DIR}/perm/perm-boot" \
  "${ROOT_DIR}/bizgraph_new" \
  "${ROOT_DIR}/base-data-service/base-data-boot"; do
  if [ -d "$dir" ]; then
    info "mvn clean: $dir"
    (cd "$dir" && mvn clean -q 2>/dev/null) || true
    xattr -cr "$dir" 2>/dev/null || true
    success "已清理: $(basename $dir)"
  fi
done

# 3. 启动所有服务（debug 模式，后台运行）
APPS="eval eval-answer eval-mcp perm bizgraph basedata"
for app in $APPS; do
  info "启动: $app"
  nohup "${SCRIPT_DIR}/run-local.sh" "$app" --debug > "/tmp/${app}.log" 2>&1 &
  sleep 2
done

info "==========================================="
info "  所有服务已在后台启动"
info "  日志: /tmp/<app>.log"
info "  Spring Boot Admin: http://localhost:9001"
info "  等待约 60 秒后查看注册状态..."
info "==========================================="

# 4. 等待并检查注册状态
sleep 60
info "检查服务端口..."
for port in 8080 8081 8082 8180 8283 8380; do
  result=$(lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)
  if [ -n "$result" ]; then
    success "端口 $port: 运行中"
  else
    warn "端口 $port: 未启动"
  fi
done

info ""
info "检查 Spring Boot Admin 注册状态..."
curl -s -H "Accept: application/json" http://localhost:9001/instances | \
  python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if not data:
        print('  暂无注册实例')
    for i in data:
        print(f\"  {i['name']:30s} 状态: {i['statusInfo']['status']}\")
except:
    print('  无法解析注册信息')
" 2>/dev/null || warn "Admin Server 未响应"

info ""
info "查看失败日志: tail -50 /tmp/<app>.log"
