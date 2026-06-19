#!/usr/bin/env bash
# ============================================================
# 本地/Docker 开发环境健康检查
# 用法：
#   ./health-check.sh dev          # 检查本地开发模式
#   ./health-check.sh full         # 检查全栈联调模式
#   ./health-check.sh wait <url>   # 等待某个服务就绪
# ============================================================
set -euo pipefail

log() { echo "[$(date '+%H:%M:%S')] $*"; }

check_url() {
    local url="$1"
    local name="$2"
    if curl -sf "$url" > /dev/null 2>&1; then
        log "  [OK] ${name} (${url})"
        return 0
    else
        log "  [FAIL] ${name} (${url})"
        return 1
    fi
}

check_port() {
    local host="$1"
    local port="$2"
    local name="$3"
    if nc -z "$host" "$port" 2>/dev/null; then
        log "  [OK] ${name} (${host}:${port})"
        return 0
    else
        log "  [FAIL] ${name} (${host}:${port})"
        return 1
    fi
}

wait_for_url() {
    local url="$1"
    local max_retries="${2:-60}"
    local interval="${3:-2}"
    log "等待 ${url} 就绪..."
    for i in $(seq 1 $max_retries); do
        if curl -sf "$url" > /dev/null 2>&1; then
            log "  ${url} 已就绪"
            return 0
        fi
        sleep "$interval"
    done
    log "  ${url} 等待超时"
    return 1
}

MODE="${1:-dev}"

case "$MODE" in
    dev)
        log "=== 本地开发模式健康检查 ==="
        check_port localhost 5432 "PostgreSQL"
        check_url http://localhost:8080/actuator/health "后端"
        check_url http://localhost:3000 "前端(Vite)"
        ;;
    full)
        log "=== 全栈联调模式健康检查 ==="
        check_port localhost 5432 "PostgreSQL"
        check_url http://localhost:8080/actuator/health "后端(直连)"
        check_url http://localhost/actuator/health "后端(Nginx)"
        check_url http://localhost "前端(Nginx)"
        ;;
    wait)
        if [ $# -lt 2 ]; then
            echo "用法: $0 wait <url> [max_retries] [interval]"
            exit 1
        fi
        wait_for_url "$2" "${3:-60}" "${4:-2}"
        ;;
    *)
        echo "用法: $0 {dev|full|wait}"
        echo "  dev   - 检查本地开发模式（PostgreSQL + 本地后端 + Vite）"
        echo "  full  - 检查全栈联调模式（Docker 全部服务 + Nginx）"
        echo "  wait  - 等待某个 URL 就绪：$0 wait <url> [retries] [interval]"
        exit 1
        ;;
esac
