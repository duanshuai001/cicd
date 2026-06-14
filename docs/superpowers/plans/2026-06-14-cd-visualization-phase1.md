# CD 可视化平台实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立统一的本地开发环境基础设施和可视化启停管理，解决端口冲突、中间件分散、缺少全局视图的痛点

**Architecture:** 分层方案 - 本地 Docker Compose + Portainer 可视化管理，云服务器 K3s + Helm Chart 预留。本地支持开发模式（IDE 启动应用）和全栈模式（Docker 启动应用），通过 Docker Compose profiles 按项目启停。

**Tech Stack:** Docker Compose, Portainer CE, PostgreSQL 16, Redis 7, Nacos v2.3.2, Bash scripts

**Spec:** `docs/superpowers/specs/2026-06-14-cd-visualization-design.md`

---

## File Structure

```
mycode_1/
├── docker-compose.infra.yml          # [修改] 增加 Portainer
├── docker-compose.apps.yml           # [新建] 统一应用编排
├── init-db.sh                        # [修改] 增加 bizgraph 数据库
└── cicd/
    └── scripts/
        ├── start-infra.sh            # [新建] 开发模式启动基础设施
        ├── start-app.sh              # [新建] 全栈模式启动指定项目
        ├── start-all.sh              # [新建] 全栈模式启动全部
        ├── stop-app.sh               # [新建] 停止指定项目
        ├── stop-all.sh               # [新建] 停止全部
        ├── rebuild.sh                # [新建] 重新构建+重启服务
        └── status.sh                 # [新建] 查看所有服务状态
```

---

### Task 1: 更新 docker-compose.infra.yml 增加 Portainer

**Files:**
- Modify: `/Users/duanshuai/mycode_1/docker-compose.infra.yml`

- [ ] **Step 1: 读取当前文件内容**

- [ ] **Step 2: 在 services 中增加 Portainer 服务，在 volumes 中增加 portainer_data**

在 `nacos` 服务后面、`volumes:` 前面插入：

```yaml
  portainer:
    image: portainer/portainer-ce:latest
    container_name: dev-portainer
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    restart: unless-stopped
```

在 `volumes:` 部分增加：

```yaml
  portainer_data:
```

- [ ] **Step 3: 验证 YAML 语法**

Run: `docker compose -f /Users/duanshuai/mycode_1/docker-compose.infra.yml config`
Expected: 输出完整的 compose 配置，无语法错误

- [ ] **Step 4: Commit**

```bash
git add docker-compose.infra.yml
git commit -m "feat: add Portainer to shared infrastructure compose"
```

---

### Task 2: 更新 init-db.sh 增加 bizgraph 数据库

**Files:**
- Modify: `/Users/duanshuai/mycode_1/init-db.sh`

- [ ] **Step 1: 在 SQL 中增加 bizgraph 数据库创建**

在 `CREATE DATABASE eval;` 后面增加：

```sql
    CREATE DATABASE bizgraph;
```

在 `GRANT ALL PRIVILEGES ON DATABASE eval TO $POSTGRES_USER;` 后面增加：

```sql
    GRANT ALL PRIVILEGES ON DATABASE bizgraph TO $POSTGRES_USER;
```

- [ ] **Step 2: Commit**

```bash
git add init-db.sh
git commit -m "feat: add bizgraph database to init script"
```

---

### Task 3: 创建 docker-compose.apps.yml 统一应用编排

**Files:**
- Create: `/Users/duanshuai/mycode_1/docker-compose.apps.yml`

- [ ] **Step 1: 创建文件**

```yaml
# ============================================================
# 统一应用编排 - 全栈模式使用
# 配合 docker-compose.infra.yml 使用
#
# 用法：
#   启动指定项目：docker compose -f docker-compose.infra.yml -f docker-compose.apps.yml --profile eval up -d
#   启动全部：    docker compose -f docker-compose.infra.yml -f docker-compose.apps.yml --profile all up -d
#   重建服务：    docker compose -f docker-compose.infra.yml -f docker-compose.apps.yml --profile eval up -d --build eval-boot
# ============================================================

services:
  # ==================== Eval（80xx）====================
  eval-boot:
    build:
      context: ${EVAL_HOME:-../eval_new}
      dockerfile: Dockerfile
    container_name: eval-boot
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/eval
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
      SPRING_PROFILES_ACTIVE: docker
      DUBBO_REGISTRY_ADDRESS: nacos://dev-nacos:8848
    ports:
      - "8080:8080"
    depends_on:
      dev-postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    profiles: ["eval", "all"]

  eval-answer-boot:
    build:
      context: ${EVAL_HOME:-../eval_new}
      dockerfile: Dockerfile.answer
    container_name: eval-answer-boot
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/eval
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
      SPRING_PROFILES_ACTIVE: docker
      DUBBO_REGISTRY_ADDRESS: nacos://dev-nacos:8848
    ports:
      - "8081:8081"
    depends_on:
      dev-postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    profiles: ["eval", "all"]

  eval-mcp-server:
    build:
      context: ${EVAL_HOME:-../eval_new}
      dockerfile: Dockerfile.mcp
    container_name: eval-mcp-server
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/eval
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
      SPRING_PROFILES_ACTIVE: docker
      DUBBO_REGISTRY_ADDRESS: nacos://dev-nacos:8848
    ports:
      - "8083:8083"
    depends_on:
      dev-postgres:
        condition: service_healthy
    profiles: ["eval", "all"]

  eval-answer-ui:
    build:
      context: ${EVAL_HOME:-../eval_new}/eval-answer-ui
      dockerfile: Dockerfile
    container_name: eval-answer-ui
    ports:
      - "8030:80"
    depends_on:
      - eval-answer-boot
      - eval-boot
    profiles: ["eval", "all"]

  # ==================== Perm（81xx）====================
  perm-boot:
    build:
      context: ${PERM_HOME:-../perm}
      dockerfile: Dockerfile
    container_name: perm-boot
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/perm
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
      SPRING_PROFILES_ACTIVE: docker
      SPRING_DATA_REDIS_HOST: dev-redis
      SPRING_DATA_REDIS_PORT: 6379
      DUBBO_REGISTRY_ADDRESS: nacos://dev-nacos:8848
    ports:
      - "8180:8180"
    depends_on:
      dev-postgres:
        condition: service_healthy
      dev-redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8180/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    profiles: ["perm", "all"]

  # ==================== BizGraph（82xx）====================
  bizgraph-backend:
    build:
      context: ${BIZGRAPH_HOME:-../bizgraph}
      dockerfile: Dockerfile
    container_name: bizgraph-backend
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/bizgraph
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
      SPRING_PROFILES_ACTIVE: docker
    ports:
      - "8280:8280"
    depends_on:
      dev-postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8280/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    profiles: ["bizgraph", "all"]

  bizgraph-frontend:
    build:
      context: ${BIZGRAPH_HOME:-../bizgraph}/frontend
      dockerfile: Dockerfile
    container_name: bizgraph-frontend
    ports:
      - "8230:80"
    depends_on:
      bizgraph-backend:
        condition: service_healthy
    profiles: ["bizgraph", "all"]

  bizgraph-mcp:
    build:
      context: ${BIZGRAPH_HOME:-../bizgraph}/bizgraph-mcp
      dockerfile: Dockerfile
    container_name: bizgraph-mcp
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/bizgraph
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
      SPRING_PROFILES_ACTIVE: docker
    ports:
      - "8283:8283"
    depends_on:
      dev-postgres:
        condition: service_healthy
    profiles: ["bizgraph", "all"]

  # ==================== Basedata（83xx）====================
  basedata-boot:
    build:
      context: ${BASEDATA_HOME:-../base-data-service}
      dockerfile: Dockerfile
    container_name: basedata-boot
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/basedata
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
      SPRING_PROFILES_ACTIVE: docker
      SPRING_DATA_REDIS_HOST: dev-redis
      SPRING_DATA_REDIS_PORT: 6379
      DUBBO_REGISTRY_ADDRESS: nacos://dev-nacos:8848
    ports:
      - "8380:8083"
    depends_on:
      dev-postgres:
        condition: service_healthy
      dev-redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8083/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    profiles: ["basedata", "all"]
```

- [ ] **Step 2: 验证 YAML 语法**

Run: `docker compose -f /Users/duanshuai/mycode_1/docker-compose.infra.yml -f /Users/duanshuai/mycode_1/docker-compose.apps.yml config`
Expected: 输出完整配置，无语法错误

- [ ] **Step 3: Commit**

```bash
git add docker-compose.apps.yml
git commit -m "feat: add unified application compose with profile-based start/stop"
```

---

### Task 4: 创建 start-infra.sh 开发模式启动脚本

**Files:**
- Create: `/Users/duanshuai/mycode_1/cicd/scripts/start-infra.sh`

- [ ] **Step 1: 创建脚本**

```bash
#!/usr/bin/env bash
# ============================================================
# 开发模式：只启动基础设施（PG/Redis/Nacos/Portainer）
# 应用在 IDE 中启动，profile=local
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 颜色定义
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

# 等待 Redis 就绪
info "等待 Redis 就绪..."
for i in $(seq 1 $max_retries); do
    if docker exec dev-redis redis-cli ping > /dev/null 2>&1; then
        success "Redis 已就绪"
        break
    fi
    if [ "$i" -eq "$max_retries" ]; then
        echo "Redis 启动超时"
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
info "  Nacos:       http://localhost:8848"
info "  Portainer:   http://localhost:9000"
echo ""
info "  下一步：在 IDE 中启动应用，profile=local"
info "  停止：docker compose -f ${ROOT_DIR}/docker-compose.infra.yml down"
```

- [ ] **Step 2: 设置可执行权限**

Run: `chmod +x /Users/duanshuai/mycode_1/cicd/scripts/start-infra.sh`

- [ ] **Step 3: Commit**

```bash
git add cicd/scripts/start-infra.sh
git commit -m "feat: add start-infra.sh for dev mode (infra only)"
```

---

### Task 5: 创建 start-app.sh 全栈模式启动脚本

**Files:**
- Create: `/Users/duanshuai/mycode_1/cicd/scripts/start-app.sh`

- [ ] **Step 1: 创建脚本**

```bash
#!/usr/bin/env bash
# ============================================================
# 全栈模式：启动基础设施 + 指定项目容器
# 用法: ./start-app.sh <项目名>
#   项目名: eval / perm / bizgraph / basedata / all
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PROFILE="${1:?Usage: $0 <eval|perm|bizgraph|basedata|all>}"

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# 验证 profile
VALID_PROFILES="eval perm bizgraph basedata all"
if ! echo " $VALID_PROFILES " | grep -q " $PROFILE "; then
    error "无效的项目名: $PROFILE"
    echo "  可选: $VALID_PROFILES"
    exit 1
fi

info "启动基础设施 + ${PROFILE} 项目容器..."
docker compose \
    -f "${ROOT_DIR}/docker-compose.infra.yml" \
    -f "${ROOT_DIR}/docker-compose.apps.yml" \
    --profile "${PROFILE}" \
    up -d

echo ""
success "==========================================="
success "  ${PROFILE} 项目已启动（全栈模式）"
success "==========================================="
echo ""
info "  Portainer:   http://localhost:9000"
info "  查看状态：./status.sh"
info "  重建服务：./rebuild.sh <服务名>"
info "  停止项目：./stop-app.sh ${PROFILE}"
```

- [ ] **Step 2: 设置可执行权限**

Run: `chmod +x /Users/duanshuai/mycode_1/cicd/scripts/start-app.sh`

- [ ] **Step 3: Commit**

```bash
git add cicd/scripts/start-app.sh
git commit -m "feat: add start-app.sh for full-stack mode with profile"
```

---

### Task 6: 创建 start-all.sh 全部启动脚本

**Files:**
- Create: `/Users/duanshuai/mycode_1/cicd/scripts/start-all.sh`

- [ ] **Step 1: 创建脚本**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/start-app.sh" all
```

- [ ] **Step 2: 设置可执行权限**

Run: `chmod +x /Users/duanshuai/mycode_1/cicd/scripts/start-all.sh`

- [ ] **Step 3: Commit**

```bash
git add cicd/scripts/start-all.sh
git commit -m "feat: add start-all.sh shortcut"
```

---

### Task 7: 创建 stop-app.sh 停止指定项目脚本

**Files:**
- Create: `/Users/duanshuai/mycode_1/cicd/scripts/stop-app.sh`

- [ ] **Step 1: 创建脚本**

```bash
#!/usr/bin/env bash
# ============================================================
# 停止指定项目容器（基础设施保持运行）
# 用法: ./stop-app.sh <项目名>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PROFILE="${1:?Usage: $0 <eval|perm|bizgraph|basedata|all>}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

info "停止 ${PROFILE} 项目容器（基础设施保持运行）..."

# 获取当前运行的该 profile 相关容器
COMPOSE_FILES="-f ${ROOT_DIR}/docker-compose.infra.yml -f ${ROOT_DIR}/docker-compose.apps.yml"

# 停止应用容器，但不停基础设施
# 使用 docker compose stop 只停容器不删
docker compose ${COMPOSE_FILES} --profile "${PROFILE}" stop

# 删除停止的应用容器（保留基础设施容器）
docker compose ${COMPOSE_FILES} --profile "${PROFILE}" rm -f

success "${PROFILE} 项目容器已停止"
info "基础设施仍在运行，停止全部请用: ./stop-all.sh"
```

- [ ] **Step 2: 设置可执行权限**

Run: `chmod +x /Users/duanshuai/mycode_1/cicd/scripts/stop-app.sh`

- [ ] **Step 3: Commit**

```bash
git add cicd/scripts/stop-app.sh
git commit -m "feat: add stop-app.sh to stop project containers only"
```

---

### Task 8: 创建 stop-all.sh 全部停止脚本

**Files:**
- Create: `/Users/duanshuai/mycode_1/cicd/scripts/stop-all.sh`

- [ ] **Step 1: 创建脚本**

```bash
#!/usr/bin/env bash
# ============================================================
# 停止全部容器（包括基础设施）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

info "停止全部容器..."
docker compose -f "${ROOT_DIR}/docker-compose.infra.yml" -f "${ROOT_DIR}/docker-compose.apps.yml" --profile all down

success "全部容器已停止"
```

- [ ] **Step 2: 设置可执行权限**

Run: `chmod +x /Users/duanshuai/mycode_1/cicd/scripts/stop-all.sh`

- [ ] **Step 3: Commit**

```bash
git add cicd/scripts/stop-all.sh
git commit -m "feat: add stop-all.sh to stop everything"
```

---

### Task 9: 创建 rebuild.sh 重建服务脚本

**Files:**
- Create: `/Users/duanshuai/mycode_1/cicd/scripts/rebuild.sh`

- [ ] **Step 1: 创建脚本**

```bash
#!/usr/bin/env bash
# ============================================================
# 重新构建+重启指定服务（加载最新代码）
# 用法:
#   ./rebuild.sh eval-boot          # 重建单个服务
#   ./rebuild.sh eval               # 重建整个项目
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TARGET="${1:?Usage: $0 <服务名|项目名>}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

COMPOSE_FILES="-f ${ROOT_DIR}/docker-compose.infra.yml -f ${ROOT_DIR}/docker-compose.apps.yml"

# 项目名到服务名映射
declare -A PROJECT_SERVICES
PROJECT_SERVICES[eval]="eval-boot eval-answer-boot eval-mcp-server eval-answer-ui"
PROJECT_SERVICES[perm]="perm-boot"
PROJECT_SERVICES[bizgraph]="bizgraph-backend bizgraph-frontend bizgraph-mcp"
PROJECT_SERVICES[basedata]="basedata-boot"

# 判断是项目名还是服务名
if [ -n "${PROJECT_SERVICES[$TARGET]+x}" ]; then
    # 是项目名，重建该项目下所有服务
    SERVICES="${PROJECT_SERVICES[$TARGET]}"
    # 找到对应的 profile
    PROFILE="$TARGET"
    info "重建 ${TARGET} 项目所有服务: ${SERVICES}"
else
    # 是服务名，需要找到对应的 profile
    SERVICES="$TARGET"
    PROFILE=""
    for proj in "${!PROJECT_SERVICES[@]}"; do
        if echo " ${PROJECT_SERVICES[$proj]} " | grep -q " $TARGET "; then
            PROFILE="$proj"
            break
        fi
    done
    if [ -z "$PROFILE" ]; then
        warn "未找到服务 ${TARGET} 对应的项目，使用 all profile"
        PROFILE="all"
    fi
    info "重建服务: ${TARGET} (profile: ${PROFILE})"
fi

# 重新构建并重启
for svc in ${SERVICES}; do
    info "重新构建 ${svc}..."
    docker compose ${COMPOSE_FILES} --profile "${PROFILE}" up -d --build "${svc}"
    success "${svc} 重建完成"
done

echo ""
success "==========================================="
success "  重建完成"
success "==========================================="
info "  查看状态：./status.sh"
info "  查看日志：docker compose ${COMPOSE_FILES} logs -f ${SERVICES%% *}"
```

- [ ] **Step 2: 设置可执行权限**

Run: `chmod +x /Users/duanshuai/mycode_1/cicd/scripts/rebuild.sh`

- [ ] **Step 3: Commit**

```bash
git add cicd/scripts/rebuild.sh
git commit -m "feat: add rebuild.sh to rebuild and restart services with latest code"
```

---

### Task 10: 创建 status.sh 状态查看脚本

**Files:**
- Create: `/Users/duanshuai/mycode_1/cicd/scripts/status.sh`

- [ ] **Step 1: 创建脚本**

```bash
#!/usr/bin/env bash
# ============================================================
# 查看所有服务状态
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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
for container in dev-postgres dev-redis dev-nacos dev-portainer; do
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
```

- [ ] **Step 2: 设置可执行权限**

Run: `chmod +x /Users/duanshuai/mycode_1/cicd/scripts/status.sh`

- [ ] **Step 3: Commit**

```bash
git add cicd/scripts/status.sh
git commit -m "feat: add status.sh to show all service status"
```

---

### Task 11: 验证基础设施启动

- [ ] **Step 1: 启动基础设施**

Run: `cd /Users/duanshuai/mycode_1 && ./cicd/scripts/start-infra.sh`
Expected: PostgreSQL、Redis、Nacos、Portainer 全部启动成功

- [ ] **Step 2: 验证 Portainer 可访问**

Run: `curl -s -o /dev/null -w "%{http_code}" http://localhost:9000`
Expected: 200 或 301（Portainer 初始化页面）

- [ ] **Step 3: 验证 PostgreSQL 数据库创建**

Run: `docker exec dev-postgres psql -U dev -c "\l"`
Expected: 列出 perm、basedata、eval、bizgraph 四个数据库

- [ ] **Step 4: 验证 Redis**

Run: `docker exec dev-redis redis-cli ping`
Expected: PONG

- [ ] **Step 5: 验证 Nacos**

Run: `curl -s -o /dev/null -w "%{http_code}" http://localhost:8848/nacos/`
Expected: 200

- [ ] **Step 6: 运行 status.sh**

Run: `cd /Users/duanshuai/mycode_1 && ./cicd/scripts/status.sh`
Expected: 显示所有基础设施服务为 ● 运行状态

---

### Task 12: 清理旧的 cicd Docker Compose 文件

**Files:**
- Modify: `/Users/duanshuai/mycode_1/cicd/docker-compose.yml` - 添加注释指向新的统一编排
- Modify: `/Users/duanshuai/mycode_1/cicd/docker-compose.dev.yml` - 添加注释指向新的统一编排

- [ ] **Step 1: 在 cicd/docker-compose.yml 顶部添加迁移说明注释**

在文件开头添加：

```yaml
# ⚠️ 已迁移：此文件仅用于 bizgraph 全栈联调
# 新的统一编排请使用根目录的 docker-compose.infra.yml + docker-compose.apps.yml
# 启动方式：./cicd/scripts/start-app.sh bizgraph
```

- [ ] **Step 2: 在 cicd/docker-compose.dev.yml 顶部添加迁移说明注释**

在文件开头添加：

```yaml
# ⚠️ 已迁移：此文件仅用于 bizgraph 本地开发
# 新的统一基础设施请使用根目录的 docker-compose.infra.yml
# 启动方式：./cicd/scripts/start-infra.sh
```

- [ ] **Step 3: Commit**

```bash
git add cicd/docker-compose.yml cicd/docker-compose.dev.yml
git commit -m "docs: add migration notes to old compose files"
```

---

## Self-Review

**1. Spec coverage:**
- 统一端口规划 → Task 3 (docker-compose.apps.yml 中端口已按 80xx/81xx/82xx/83xx 分段)
- Portainer 可视化 → Task 1 (增加 Portainer 服务) + Task 11 (验证)
- 开发模式/全栈模式 → Task 4 (start-infra.sh) + Task 5 (start-app.sh)
- 重建服务加载最新代码 → Task 9 (rebuild.sh)
- 启停脚本 → Task 4-8
- 状态查看 → Task 10 (status.sh)
- init-db.sh 增加 bizgraph → Task 2

**2. Placeholder scan:** 无 TBD/TODO/placeholder

**3. Type consistency:** 所有脚本使用一致的容器名、profile 名、compose 文件路径
