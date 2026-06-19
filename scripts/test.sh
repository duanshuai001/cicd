# ============================================================
# 测试调度器
# 用法：./test.sh <stage>
#   stage: unit | integration | e2e | auto
#
# auto 模式：先调用 diff-scope.sh 判断跑哪些
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CICD_HOME="$(cd "${SCRIPT_DIR}/.." && pwd)"
export BIZGRAPH_HOME="${BIZGRAPH_HOME:-$(cd "${CICD_HOME}/../bizgraph" 2>/dev/null && pwd || echo "")}"

STAGE="${1:-auto}"
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ---------- 单元测试 ----------
run_unit() {
    log "=== 单元测试 ==="
    cd "${BIZGRAPH_HOME}"
    mvn test -Dtest='*Test' -DfailIfNoTests=false
}

# ---------- 集成测试 ----------
run_integration() {
    log "=== 集成测试 ==="

    # 1. 确保 PostgreSQL 在跑
    if ! nc -z localhost 5432 2>/dev/null; then
        log "PostgreSQL 未启动，先起基础设施..."
        docker compose -f "${CICD_HOME}/docker-compose.dev.yml" up -d
        "${CICD_HOME}/scripts/health-check-dev.sh" wait http://localhost:8080/actuator/health 2>/dev/null || true
        "${CICD_HOME}/scripts/health-check-dev.sh" wait "tcp://localhost:5432" 30 1 2>/dev/null || \
            until docker exec bizgraph-postgres pg_isready -U postgres; do sleep 1; done
    fi

    cd "${BIZGRAPH_HOME}"
    mvn verify -Pintegration-test
}

# ---------- E2E 测试 ----------
run_e2e() {
    log "=== E2E 测试（Playwright）==="

    # 1. 全栈启动
    cd "${CICD_HOME}"
    if ! curl -sf http://localhost/actuator/health > /dev/null 2>&1; then
        log "全栈未启动，先起..."
        "${CICD_HOME}/scripts/dev-full.sh"
    fi

    # 2. 跑 Playwright
    cd "${BIZGRAPH_HOME}/frontend"
    npx playwright test
}

# ---------- auto 模式 ----------
run_auto() {
    log "=== Auto 模式：分析改动范围 ==="
    local scope_json
    scope_json=$("${SCRIPT_DIR}/diff-scope.sh" 2>/dev/null || echo '{"stages":["unit"]}')

    local stages
    stages=$(echo "${scope_json}" | jq -r '.stages | join(" ")')
    local scope
    scope=$(echo "${scope_json}" | jq -r '.scope')

    log "判定结果: scope=${scope}, stages=[${stages}]"
    log "改动文件:"
    echo "${scope_json}" | jq -r '.changed_files[]' | sed 's/^/  - /'

    for stage in ${stages}; do
        case "${stage}" in
            unit)        run_unit ;;
            integration) run_integration ;;
            e2e)         run_e2e ;;
        esac
    done
}

# ---------- 入口 ----------
case "${STAGE}" in
    unit)        run_unit ;;
    integration) run_integration ;;
    e2e)         run_e2e ;;
    auto)        run_auto ;;
    *)
        echo "用法: $0 {unit|integration|e2e|auto}"
        exit 1
        ;;
esac
