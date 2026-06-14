#!/usr/bin/env bash
# ============================================================
# 开发模式：用 mvn 本地启动应用（AI/终端可调用）
# 用法:
#   ./run-local.sh eval              # 启动 eval-boot
#   ./run-local.sh perm              # 启动 perm-boot
#   ./run-local.sh basedata          # 启动 basedata-boot
#   ./run-local.sh bizgraph          # 启动 bizgraph-backend
#   ./run-local.sh bizgraph-mcp      # 启动 bizgraph-mcp
#   ./run-local.sh eval-answer       # 启动 eval-answer-boot
#   ./run-local.sh eval-mcp          # 启动 eval-mcp-server
#
# Debug 模式:
#   ./run-local.sh eval --debug      # 启用 JDWP 远程调试（端口 5005）
#
# 注意：
#   - 需要先执行 start-infra.sh 启动基础设施
#   - profile=local 读取 application-local.yml
#   - 如果项目没有 application-local.yml，会使用 application.yml
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
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# 解析参数
APP=""
DEBUG=false
DEBUG_PORT="5005"

for arg in "$@"; do
    case $arg in
        --debug)
            DEBUG=true
            shift
            ;;
        --debug=*)
            DEBUG=true
            DEBUG_PORT="${arg#*=}"
            shift
            ;;
        --help|-h)
            info "用法: $0 <应用名> [--debug[=<端口>]]"
            echo "  应用名: eval | eval-answer | eval-mcp | perm | bizgraph | bizgraph-mcp | basedata"
            echo "  --debug: 启用远程调试（默认端口 5005）"
            exit 0
            ;;
        *)
            if [ -z "$APP" ]; then
                APP="$arg"
            fi
            ;;
    esac
done

APP="${APP:?Usage: $0 <eval|perm|basedata|bizgraph|bizgraph-mcp|eval-answer|eval-mcp> [--debug]}"

# 检查基础设施是否运行
info "检查基础设施状态..."
if ! docker ps --format "{{.Names}}" | grep -q "^dev-postgres$"; then
    error "dev-postgres 未运行，请先执行: ./cicd/scripts/start-infra.sh"
fi
success "基础设施运行中"

# 项目配置：项目名 -> (工作目录, Maven模块, 启动类, 端口)
declare -A PROJECTS
PROJECTS[eval]="${ROOT_DIR}/eval_new|eval-boot|com.eval.EvalApplication|8080"
PROJECTS[eval-answer]="${ROOT_DIR}/eval_new|eval-answer-boot|com.eval.AnswerApplication|8081"
PROJECTS[eval-mcp]="${ROOT_DIR}/eval_new|eval-mcp-server|com.eval.mcp.McpServerApplication|8083"
PROJECTS[perm]="${ROOT_DIR}/perm|perm-boot|com.perm.boot.PermBootApplication|8180"
PROJECTS[bizgraph]="${ROOT_DIR}/bizgraph|.|com.bizgraph.BizGraphApplication|8280"
PROJECTS[bizgraph-mcp]="${ROOT_DIR}/bizgraph/bizgraph-mcp|.|com.bizgraph.mcp.BizGraphMcpApplication|8283"
PROJECTS[basedata]="${ROOT_DIR}/base-data-service|base-data-boot|com.basedata.boot.BaseDataBootApplication|8380"

if [ -z "${PROJECTS[$APP]+x}" ]; then
    error "未知应用: $APP"
    echo "  可选: ${!PROJECTS[*]}"
    exit 1
fi

IFS='|' read -r APP_DIR MVN_MODULE MAIN_CLASS PORT <<< "${PROJECTS[$APP]}"

info "==========================================="
info "  启动应用: $APP"
info "  工作目录: $APP_DIR"
info "  模块: $MVN_MODULE"
info "  主类: $MAIN_CLASS"
info "  端口: $PORT"
info "  Profile: local"
info "==========================================="

cd "${APP_DIR}"

# 检查是否存在 application-local.yml，没有就用 application.yml
if [ -f "${MVN_MODULE}/src/main/resources/application-local.yml" ]; then
    PROFILE="local"
elif [ "$MVN_MODULE" = "." ] && [ -f "src/main/resources/application-local.yml" ]; then
    PROFILE="local"
else
    warn "未找到 application-local.yml，将使用默认 application.yml"
    PROFILE="local"
fi

# JVM 参数
JVM_ARGS="-Xms512m -Xmx1024m"

if [ "$DEBUG" = true ]; then
    info "启用远程调试模式（JDWP 端口: ${DEBUG_PORT}）"
    info "  IDE 调试配置: localhost:${DEBUG_PORT} (Attach to remote JVM)"
    JVM_ARGS="${JVM_ARGS} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:${DEBUG_PORT}"
fi

# 启动应用
cd "${APP_DIR}"
mvn spring-boot:run \
    -pl "${MVN_MODULE}" \
    -am \
    -Dspring-boot.run.profiles="${PROFILE}" \
    -Dspring-boot.run.jvmArguments="${JVM_ARGS}" \
    2>&1 | sed "s/^/  /"
