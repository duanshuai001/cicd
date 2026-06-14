# CD 可视化平台设计文档

## 背景

当前有 7 个项目（eval_new、perm、base-data-service、bizgraph、bizgraph_new、idea_codegraph、cicd），存在以下痛点：
1. 端口冲突导致启停混乱（8080/8081/8083/3000/5432 多项目复用）
2. 缺少服务状态全局视图
3. 部署流程手动化
4. 中间件管理分散（各项目自带 PG/Redis/Nacos）

CI 侧已完成（GitHub Actions 可复用工作流），CD 侧需要可视化的应用部署与启停管理。

## 方案选择

采用**分层方案**：本地 Docker Compose + Portainer 可视化，云服务器 K3s + Helm Chart。

| 环境 | 编排方式 | 可视化 | 适用场景 |
|------|---------|--------|---------|
| 本地开发 | Docker Compose | Portainer | 日常开发调试 |
| 云服务器 | K3s + Helm | kubectl + Portainer Agent | 测试/预发/生产 |

## 一、统一端口规划

按项目分段分配端口，避免冲突：

| 服务 | 宿主端口 | 容器端口 | 项目 |
|------|---------|---------|------|
| **基础设施** | | | |
| PostgreSQL | 5432 | 5432 | 共享 |
| Redis | 6379 | 6379 | 共享 |
| Nacos | 8848/9848 | 8848/9848 | 共享 |
| Portainer | 9000 | 9000 | 可视化管理 |
| **Eval（80xx）** | | | |
| eval-boot | 8080 | 8080 | 评价主服务 |
| eval-answer-boot | 8081 | 8081 | 答题服务 |
| eval-mcp-server | 8083 | 8083 | 评价 MCP |
| eval-answer-ui | 8030 | 80 | 答题前端 |
| **Perm（81xx）** | | | |
| perm-boot | 8180 | 8180 | 权限服务 |
| **BizGraph（82xx）** | | | |
| bizgraph-backend | 8280 | 8280 | 业务建模后端 |
| bizgraph-frontend | 8230 | 80 | 业务建模前端 |
| bizgraph-mcp | 8283 | 8283 | 业务建模 MCP |
| bizgraph_new | 8281 | 8281 | 新版 BizGraph |
| **Basedata** | | | |
| basedata-boot | 8083→待定 | 8083 | 基础数据服务 |

> 注：basedata-boot 当前端口 8083 与 eval-mcp-server 冲突，需调整。建议改为 8380（Basedata=83xx 段）。

## 二、本地开发环境

### 2.1 运行模式

本地支持两种运行模式，按需切换：

| 模式 | 基础设施 | 应用 | 适用场景 |
|------|---------|------|---------|
| **开发模式** | Docker 容器 | IDE 启动 | 日常开发，改代码实时生效 |
| **全栈模式** | Docker 容器 | Docker 容器 | 联调/演示，一键启动完整环境 |

- **开发模式**：`start-infra.sh` 只起 PG/Redis/Nacos/Portainer，应用在 IDE 中启动（profile=local）
- **全栈模式**：`start-app.sh eval` 起基础设施 + eval 全部容器，Portainer 统一管理

### 2.2 文件结构

```
mycode_1/
├── docker-compose.infra.yml     # 基础设施（PG/Redis/Nacos/Portainer）
├── docker-compose.apps.yml      # 所有应用服务（全栈模式用）
├── init-db.sh                   # PG 初始化（创建所有数据库）
└── cicd/
    └── scripts/
        ├── start-infra.sh       # 开发模式：只启动基础设施
        ├── start-app.sh <项目>  # 全栈模式：启动基础设施+指定项目
        ├── start-all.sh         # 全栈模式：启动全部
        ├── stop-app.sh <项目>   # 停止指定项目
        ├── stop-all.sh          # 停止全部
        ├── rebuild.sh <服务名>  # 重新构建+重启指定服务（加载最新代码）
        └── status.sh            # 查看所有服务状态
```

### 2.3 docker-compose.infra.yml

统一基础设施，替代各项目自带的中间件：

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: dev-postgres
    environment:
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init-db.sh:/docker-entrypoint-initdb.d/init-db.sh
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev"]
      interval: 5s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    container_name: dev-redis
    command: ["redis-server", "--appendonly", "yes"]
    ports:
      - "6379:6379"
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  nacos:
    image: nacos/nacos-server:v2.3.2
    container_name: dev-nacos
    environment:
      MODE: standalone
      JVM_XMS: 256m
      JVM_XMX: 512m
    ports:
      - "8848:8848"
      - "9848:9848"

  portainer:
    image: portainer/portainer-ce:latest
    container_name: dev-portainer
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    restart: unless-stopped

volumes:
  pgdata:
  redisdata:
  portainer_data:
```

### 2.4 init-db.sh

```bash
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE perm;
    CREATE DATABASE basedata;
    CREATE DATABASE eval;
    CREATE DATABASE bizgraph;
    GRANT ALL PRIVILEGES ON DATABASE perm TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE basedata TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE eval TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE bizgraph TO $POSTGRES_USER;
EOSQL
```

### 2.5 docker-compose.apps.yml

所有应用服务统一编排，每个服务连接统一基础设施：

```yaml
services:
  # ==================== Eval ====================
  eval-boot:
    build:
      context: ${EVAL_HOME:-../eval_new}
      dockerfile: Dockerfile
    container_name: eval-boot
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/eval
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
      DUBBO_REGISTRY_ADDRESS: nacos://dev-nacos:8848
    ports:
      - "8080:8080"
    depends_on:
      dev-postgres:
        condition: service_healthy
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
      DUBBO_REGISTRY_ADDRESS: nacos://dev-nacos:8848
    ports:
      - "8081:8081"
    depends_on:
      dev-postgres:
        condition: service_healthy
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

  # ==================== Perm ====================
  perm-boot:
    build:
      context: ${PERM_HOME:-../perm}
      dockerfile: Dockerfile
    container_name: perm-boot
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/perm
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
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
    profiles: ["perm", "all"]

  # ==================== BizGraph ====================
  bizgraph-backend:
    build:
      context: ${BIZGRAPH_HOME:-../bizgraph}
      dockerfile: Dockerfile
    container_name: bizgraph-backend
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/bizgraph
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
    ports:
      - "8280:8280"
    depends_on:
      dev-postgres:
        condition: service_healthy
    profiles: ["bizgraph", "all"]

  bizgraph-frontend:
    build:
      context: ${BIZGRAPH_HOME:-../bizgraph}/frontend
      dockerfile: Dockerfile
    container_name: bizgraph-frontend
    ports:
      - "8230:80"
    depends_on:
      - bizgraph-backend
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
    ports:
      - "8283:8283"
    depends_on:
      dev-postgres:
        condition: service_healthy
    profiles: ["bizgraph", "all"]

  # ==================== Basedata ====================
  basedata-boot:
    build:
      context: ${BASEDATA_HOME:-../base-data-service}
      dockerfile: Dockerfile
    container_name: basedata-boot
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://dev-postgres:5432/basedata
      SPRING_DATASOURCE_USERNAME: dev
      SPRING_DATASOURCE_PASSWORD: dev
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
    profiles: ["basedata", "all"]
```

> 使用 Docker Compose profiles 实现按项目启停：`docker compose --profile eval up -d`

### 2.6 Portainer 可视化

访问 `http://localhost:9000`，提供：
- **Dashboard**：所有容器状态一览（运行/停止/异常）
- **一键启停**：点击按钮启动/停止/重启任意容器
- **日志查看**：实时查看容器日志
- **终端接入**：Web 终端直接进入容器调试
- **资源监控**：CPU/内存使用情况
- **镜像管理**：拉取最新镜像、更新容器

### 2.7 启停与重建脚本

```bash
# ===== 开发模式 =====
# 启动基础设施（PG/Redis/Nacos/Portainer），应用在 IDE 启动
./start-infra.sh
# 等同于：docker compose -f docker-compose.infra.yml up -d

# ===== 全栈模式 =====
# 启动指定项目（基础设施 + 应用容器）
./start-app.sh eval
# 等同于：docker compose -f docker-compose.infra.yml -f docker-compose.apps.yml --profile eval up -d

# 启动全部
./start-all.sh
# 等同于：docker compose -f docker-compose.infra.yml -f docker-compose.apps.yml --profile all up -d

# ===== 停止 =====
# 停止指定项目（只停应用容器，基础设施保持运行）
./stop-app.sh eval

# 停止全部（包括基础设施）
./stop-all.sh

# ===== 重建（加载最新代码）=====
# 重新构建指定服务镜像并重启，用于全栈模式下更新代码
./rebuild.sh eval-boot
# 等同于：docker compose -f docker-compose.infra.yml -f docker-compose.apps.yml --profile eval up -d --build eval-boot

# 重建整个项目
./rebuild.sh eval
# 重建 eval 项目下所有服务

# ===== 状态查看 =====
./status.sh
# 显示所有容器状态（运行/停止/端口映射）
```

### 2.8 各项目配置适配

各项目需新增 `application-docker.yml`，连接统一基础设施：

**eval_new/application-docker.yml**：
```yaml
spring:
  datasource:
    url: jdbc:postgresql://dev-postgres:5432/eval
    username: dev
    password: dev
dubbo:
  registry:
    address: nacos://dev-nacos:8848
```

**perm/application-docker.yml**：
```yaml
spring:
  datasource:
    url: jdbc:postgresql://dev-postgres:5432/perm
    username: dev
    password: dev
  data:
    redis:
      host: dev-redis
      port: 6379
dubbo:
  registry:
    address: nacos://dev-nacos:8848
```

**base-data-service/application-docker.yml**：
```yaml
spring:
  datasource:
    url: jdbc:postgresql://dev-postgres:5432/basedata
    username: dev
    password: dev
  data:
    redis:
      host: dev-redis
      port: 6379
dubbo:
  registry:
    address: nacos://dev-nacos:8848
```

**bizgraph/application-docker.yml**：
```yaml
spring:
  datasource:
    url: jdbc:postgresql://dev-postgres:5432/bizgraph
    username: dev
    password: dev
```

## 三、云服务器部署（K3s + Helm）

### 3.1 架构

```
云服务器 (K3s)
├── Namespace: infra
│   └── PG (StatefulSet) / Redis / Nacos
├── Namespace: eval
│   └── eval-boot / eval-answer-boot / eval-mcp-server / eval-answer-ui
├── Namespace: perm
│   └── perm-boot
├── Namespace: bizgraph
│   └── bizgraph-backend / bizgraph-frontend / bizgraph-mcp
└── Namespace: basedata
    └── basedata-boot
```

### 3.2 Helm Chart 结构

```
cicd/helm/
├── charts/
│   ├── infra/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── postgres-statefulset.yaml
│   │       ├── redis-deployment.yaml
│   │       └── nacos-deployment.yaml
│   ├── eval/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── ingress.yaml
│   ├── perm/
│   ├── basedata/
│   └── bizgraph/
└── environments/
    ├── dev-values.yaml
    ├── staging-values.yaml
    └── prod-values.yaml
```

### 3.3 部署命令

```bash
# 部署基础设施
helm install infra cicd/helm/charts/infra -n infra --create-namespace

# 部署 eval 项目
helm install eval cicd/helm/charts/eval -n eval --create-namespace \
  -f cicd/helm/environments/dev-values.yaml

# 升级
helm upgrade eval cicd/helm/charts/eval -n eval \
  -f cicd/helm/environments/dev-values.yaml

# 回滚
helm rollback eval -n eval
```

## 四、CI/CD 流水线

### 4.1 分支策略与触发规则

| 事件 | 触发的流水线 | 说明 |
|------|------------|------|
| `feature/*` 推送 | 编译 + 单元测试 | 快速反馈 |
| PR 到 `develop` | 编译 + 测试 + Lint | PR 质量门禁 |
| 合并到 `develop` | 编译 + 测试 + 构建镜像 + 推送 ghcr.io | 开发环境镜像就绪 |
| 合并到 `main` | 编译 + 测试 + 安全扫描 + 构建镜像 + 部署 staging | 自动部署预发 |
| `v*` 标签 | 构建镜像 + 创建 Release + 部署 prod（需审批） | 正式发版 |

### 4.2 CI/CD 模式

| 环境 | CI | CD | 说明 |
|------|----|----|------|
| 本地开发 | GitHub Actions 自动构建推镜像 | Portainer 手动拉取 | 半自动 |
| 云服务器 | GitHub Actions 自动构建推镜像 | helm upgrade 自动部署 | 全自动 |

### 4.3 各项目 CI 工作流

每个业务项目创建 `.github/workflows/ci.yml`，引用 cicd 仓库共享工作流：

```yaml
# eval_new/.github/workflows/ci.yml
name: Eval CI
on:
  push:
    branches: [develop, main]
  pull_request:
    branches: [develop]

jobs:
  build:
    uses: <org>/cicd/.github/workflows/build-java.yml@main
    with:
      maven-modules: "eval-boot,eval-answer-boot,eval-mcp-server"
      java-version: "21"

  docker:
    needs: build
    if: github.event_name == 'push'
    strategy:
      matrix:
        service: [eval-boot, eval-answer-boot, eval-mcp-server]
    uses: <org>/cicd/.github/workflows/build-docker.yml@main
    with:
      image-name: eval/${{ matrix.service }}
      dockerfile-path: docker/Dockerfile.${{ matrix.service }}
      download-artifact-name: build-artifacts
```

### 4.4 cicd 仓库扩展

| 新增/修改 | 说明 |
|----------|------|
| `deploy-helm.yml` | 替代 `deploy-k8s.yml`，使用 Helm 部署 |
| `docker-compose.apps.yml` | 统一应用编排文件 |
| `helm/charts/` | 各项目 Helm Chart |
| `init-db.sh` | 增加 bizgraph 数据库 |
| 各项目 `application-docker.yml` | 连接统一基础设施 |

## 五、实施计划

| 阶段 | 内容 | 依赖 |
|------|------|------|
| Phase 1 | 统一基础设施 + 端口规划 + Portainer | 无 |
| Phase 2 | 各项目 application-docker.yml + docker-compose.apps.yml | Phase 1 |
| Phase 3 | 各项目 CI 工作流对接 | Phase 2 |
| Phase 4 | Helm Charts + 云服务器部署 | 购买云服务器后 |

### Phase 1 详细任务

1. 更新 `docker-compose.infra.yml`：增加 Portainer 服务
2. 更新 `init-db.sh`：增加 bizgraph 数据库
3. 创建 `docker-compose.apps.yml`：统一应用编排
4. 创建启停脚本：start-infra.sh / start-app.sh / start-all.sh / stop-app.sh / stop-all.sh / status.sh
5. 验证：启动基础设施 → 启动各项目 → Portainer 查看状态

### Phase 2 详细任务

1. eval_new：新增 application-docker.yml，调整 Dubbo 注册中心为 Nacos
2. perm：新增 application-docker.yml，调整端口为 8180
3. base-data-service：新增 application-docker.yml，调整端口为 8380
4. bizgraph：新增 application-docker.yml，调整端口为 8280
5. 各项目新增 Dockerfile（多阶段构建）
6. 验证：docker compose --profile <项目> up -d 全部正常

### Phase 3 详细任务

1. 各项目创建 .github/workflows/ci.yml
2. cicd 仓库新增 deploy-helm.yml
3. 配置 GitHub Secrets（KUBECONFIG）
4. 验证：推送代码 → Actions 触发 → 镜像构建 → Portainer 拉取

### Phase 4 详细任务

1. 云服务器安装 K3s
2. 创建 Helm Charts
3. 配置 Ingress + 域名
4. 验证：推送 main → 自动部署 staging
