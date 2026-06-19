#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- 配置 ----
EVAL_NEW_HOME="${EVAL_NEW_HOME:-$(cd "$SCRIPT_DIR/../../eval_new" 2>/dev/null && pwd || echo "")}"
TARGET_HOST="${TARGET_HOST:-localhost}"
MANAGE_PORT="${MANAGE_PORT:-8080}"
ANSWER_PORT="${ANSWER_PORT:-8081}"

# ---- 命令 ----

cmd_deploy() {
    info "部署 eval_new 到笔记本..."
    if [ -z "$EVAL_NEW_HOME" ]; then
        error "找不到 eval_new 项目，请设置 EVAL_NEW_HOME 环境变量"
        exit 1
    fi
    info "eval_new 路径: $EVAL_NEW_HOME"

    export EVAL_NEW_HOME
    docker compose -f docker-compose.perf.yml up --build -d

    info "等待服务启动..."
    sleep 10

    # 健康检查
    local retries=30
    while [ $retries -gt 0 ]; do
        if curl -sf "http://${TARGET_HOST}:${MANAGE_PORT}/actuator/health" > /dev/null 2>&1; then
            info "eval-boot (管理端) 已就绪: http://${TARGET_HOST}:${MANAGE_PORT}"
            break
        fi
        retries=$((retries - 1))
        sleep 2
    done

    retries=30
    while [ $retries -gt 0 ]; do
        if curl -sf "http://${TARGET_HOST}:${ANSWER_PORT}/actuator/health" > /dev/null 2>&1; then
            info "eval-answer-boot (答题端) 已就绪: http://${TARGET_HOST}:${ANSWER_PORT}"
            break
        fi
        retries=$((retries - 1))
        sleep 2
    done

    info "部署完成！"
}

cmd_teardown() {
    info "停止并清理 eval_new 服务..."
    export EVAL_NEW_HOME
    docker compose -f docker-compose.perf.yml down -v
    info "已清理"
}

cmd_baseline() {
    info "启动基准摸底压测..."
    info "目标: http://${TARGET_HOST}:${MANAGE_PORT}"
    locust \
        -f locust_baseline.py \
        --host="http://${TARGET_HOST}:${MANAGE_PORT}" \
        --web-port=8089 \
        --tags="scenario" "template" "task" "person" "org" "tracking" "result"
}

cmd_answer() {
    info "启动答题并发压测..."
    info "数据准备: http://${TARGET_HOST}:${MANAGE_PORT}"
    info "答题端: http://${TARGET_HOST}:${ANSWER_PORT}"
    locust \
        -f locust_answer.py \
        --host="http://${TARGET_HOST}:${ANSWER_PORT}" \
        --web-port=8089
}

cmd_headless_baseline() {
    local users="${1:-50}"
    local spawn_rate="${2:-5}"
    local run_time="${3:-5m}"
    info "无头模式基准压测: ${users} 用户, ${spawn_rate}/s 增长, 持续 ${run_time}"
    locust \
        -f locust_baseline.py \
        --host="http://${TARGET_HOST}:${MANAGE_PORT}" \
        --headless \
        -u "$users" \
        -r "$spawn_rate" \
        -t "$run_time" \
        --csv="results/baseline_${users}u" \
        --html="results/baseline_${users}u.html"
    info "结果已保存到 results/ 目录"
}

cmd_headless_answer() {
    local users="${1:-100}"
    local spawn_rate="${2:-10}"
    local run_time="${3:-5m}"
    info "无头模式答题压测: ${users} 用户, ${spawn_rate}/s 增长, 持续 ${run_time}"
    locust \
        -f locust_answer.py \
        --host="http://${TARGET_HOST}:${ANSWER_PORT}" \
        --headless \
        -u "$users" \
        -r "$spawn_rate" \
        -t "$run_time" \
        --csv="results/answer_${users}u" \
        --html="results/answer_${users}u.html"
    info "结果已保存到 results/ 目录"
}

cmd_status() {
    info "检查服务状态..."
    echo ""

    # 检查 eval-boot
    if curl -sf "http://${TARGET_HOST}:${MANAGE_PORT}/actuator/health" > /dev/null 2>&1; then
        info "eval-boot (管理端): 正常  http://${TARGET_HOST}:${MANAGE_PORT}"
    else
        warn "eval-boot (管理端): 不可达  http://${TARGET_HOST}:${MANAGE_PORT}"
    fi

    # 检查 eval-answer-boot
    if curl -sf "http://${TARGET_HOST}:${ANSWER_PORT}/actuator/health" > /dev/null 2>&1; then
        info "eval-answer-boot (答题端): 正常  http://${TARGET_HOST}:${ANSWER_PORT}"
    else
        warn "eval-answer-boot (答题端): 不可达  http://${TARGET_HOST}:${ANSWER_PORT}"
    fi

    # 检查 PostgreSQL
    if docker compose -f docker-compose.perf.yml ps dev-postgres 2>/dev/null | grep -q "running"; then
        info "PostgreSQL: 运行中"
    else
        warn "PostgreSQL: 未运行"
    fi
}

cmd_install() {
    info "安装 Locust..."
    pip3 install locust
    info "安装完成，版本: $(locust --version 2>&1 || echo '未知')"
}

# ---- 主入口 ----

usage() {
    echo "eval_new 性能测试工具"
    echo ""
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  deploy              部署 eval_new 到笔记本 (Docker Compose)"
    echo "  teardown            停止并清理服务"
    echo "  status              检查服务状态"
    echo "  install             安装 Locust 依赖"
    echo ""
    echo "  baseline            启动基准摸底压测 (Web UI, 端口 8089)"
    echo "  answer              启动答题并发压测 (Web UI, 端口 8089)"
    echo ""
    echo "  headless-baseline [users] [spawn_rate] [run_time]"
    echo "                      无头模式基准压测 (默认: 50 用户, 5/s, 5m)"
    echo "  headless-answer  [users] [spawn_rate] [run_time]"
    echo "                      无头模式答题压测 (默认: 100 用户, 10/s, 5m)"
    echo ""
    echo "环境变量:"
    echo "  EVAL_NEW_HOME       eval_new 项目路径 (默认: ../../eval_new)"
    echo "  TARGET_HOST         目标主机 (默认: localhost)"
    echo "  MANAGE_PORT         管理端端口 (默认: 8080)"
    echo "  ANSWER_PORT         答题端端口 (默认: 8081)"
}

# 创建结果目录
mkdir -p "$SCRIPT_DIR/results"

case "${1:-}" in
    deploy)           cmd_deploy ;;
    teardown)         cmd_teardown ;;
    status)           cmd_status ;;
    install)          cmd_install ;;
    baseline)         cmd_baseline ;;
    answer)           cmd_answer ;;
    headless-baseline) cmd_headless_baseline "${2:-50}" "${3:-5}" "${4:-5m}" ;;
    headless-answer)  cmd_headless_answer "${2:-100}" "${3:-10}" "${4:-5m}" ;;
    *)                usage ;;
esac
