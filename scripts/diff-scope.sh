#!/usr/bin/env bash
# ============================================================
# 改动范围分析器
# 用法：./diff-scope.sh [BASE_BRANCH]
#   BASE_BRANCH 默认 origin/main
#
# 输出：JSON 格式的改动范围和推荐的测试阶段
# {
#   "scope": "backend-internal | backend-api | frontend | fullstack | infra",
#   "stages": ["unit","integration","e2e"],
#   "changed_files": [...]
# }
# ============================================================
set -euo pipefail

BASE_BRANCH="${1:-HEAD}"

cd "${BIZGRAPH_HOME:-/Users/duanshuai/mycode_1/bizgraph}"

# 1. 获取改动文件列表（覆盖：未暂存 + 已暂存 + 与指定基线对比）
CHANGED_FILES=$(git diff --name-only "${BASE_BRANCH}" 2>/dev/null || echo "")
# 补充：已暂存但还没提交的文件
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")
CHANGED_FILES=$(printf "%s\n%s\n" "${CHANGED_FILES}" "${STAGED_FILES}" | grep -v '^$' | sort -u)

if [ -z "${CHANGED_FILES}" ]; then
    echo '{"scope":"none","stages":[],"changed_files":[]}'
    exit 0
fi

# 2. 分类
BACKEND_INTERNAL=0
BACKEND_API=0
FRONTEND=0
INFRA=0
DB_MIGRATION=0

while IFS= read -r file; do
    case "$file" in
        # 后端内部：domain / service 实现 / util
        src/main/java/com/bizgraph/domain/*|\
src/main/java/com/bizgraph/infrastructure/*|\
src/main/java/com/bizgraph/util/*)
            BACKEND_INTERNAL=1
            ;;
        # 后端 API：Controller / DTO / Repository
        src/main/java/com/bizgraph/api/*|\
src/main/java/com/bizgraph/interfaces/*|\
src/main/java/com/bizgraph/dto/*|\
src/main/java/com/bizgraph/repository/*|\
src/main/java/com/bizgraph/controller/*)
            BACKEND_API=1
            ;;
        # 数据库迁移
        src/main/resources/db/migration/*)
            DB_MIGRATION=1
            BACKEND_API=1
            ;;
        # 前端
        frontend/src/*)
            FRONTEND=1
            ;;
        # 基础设施
        Dockerfile|docker-compose*.yml|nginx.conf|frontend/Dockerfile|frontend/nginx.conf|.env*)
            INFRA=1
            ;;
        # 配置文件
        src/main/resources/application*.yml|pom.xml)
            BACKEND_API=1
            ;;
    esac
done <<< "${CHANGED_FILES}"

# 3. 推断 scope 和 stages
STAGES=()

if [ "${BACKEND_INTERNAL}" = "1" ] || [ "${BACKEND_API}" = "1" ]; then
    STAGES+=("unit")
fi

if [ "${BACKEND_API}" = "1" ] || [ "${DB_MIGRATION}" = "1" ]; then
    STAGES+=("integration")
fi

if [ "${FRONTEND}" = "1" ] || [ "${BACKEND_API}" = "1" ] || [ "${INFRA}" = "1" ]; then
    STAGES+=("e2e")
fi

if [ "${INFRA}" = "1" ]; then
    SCOPE="infra"
elif [ "${FRONTEND}" = "1" ] && [ "${BACKEND_API}" = "1" ]; then
    SCOPE="fullstack"
elif [ "${FRONTEND}" = "1" ]; then
    SCOPE="frontend"
elif [ "${BACKEND_API}" = "1" ]; then
    SCOPE="backend-api"
elif [ "${BACKEND_INTERNAL}" = "1" ]; then
    SCOPE="backend-internal"
else
    SCOPE="unknown"
fi

# 4. 输出 JSON
CHANGED_JSON=$(echo "${CHANGED_FILES}" | jq -R . | jq -s .)
STAGES_JSON=$(printf '%s\n' "${STAGES[@]+"${STAGES[@]}"}" | jq -R . | jq -s .)

cat <<EOF
{
  "scope": "${SCOPE}",
  "stages": ${STAGES_JSON},
  "changed_files": ${CHANGED_JSON}
}
EOF
