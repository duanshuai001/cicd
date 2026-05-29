# Eval 系统 CI/CD 公共平台集成 Spec

## Why
Eval 后端系统已开发完成，需要建立一套**公共 CI/CD 平台**，以共享可复用工作流的方式为 Eval 及后续项目提供自动化构建、测试、安全扫描和部署能力。项目已有 `ci/` 目录下的脚本、K8s 配置和 Docker 文件，但缺少 `.github/workflows/` 中的 GitHub Actions 工作流文件，且现有可复用模板存放在 `ci/templates/` 中未被 GitHub Actions 直接使用。

## 架构决策

### 决策 1：公共 CI/CD 平台（双仓库架构）

1. **共享 CI/CD 仓库**（当前工作目录 `mycode_1/cicd`）：存放所有可复用工作流、共享脚本和文档
   ```
   cicd/
   ├── .github/
   │   └── workflows/
   │       ├── build-java.yml        # 可复用：Java Maven 构建
   │       ├── build-docker.yml      # 可复用：Docker 镜像构建推送
   │       ├── deploy-k8s.yml        # 可复用：K8s 部署（预留，K8s 就绪后启用）
   │       └── security-scan.yml     # 可复用：安全扫描
   ├── scripts/                      # 共享脚本（从 eval/ci/scripts/ 迁移优化）
   │   ├── build.sh
   │   ├── deploy.sh
   │   ├── health-check.sh
   │   ├── notify.sh
   │   └── rollback.sh
   ├── config/                       # 共享配置模板
   │   ├── environments.yml
   │   └── notifications.yml
   └── docs/                         # 使用文档和接入指南
   ```

2. **业务项目仓库**（如 `mycode/eval`）：存放项目专属工作流和配置
   ```
   eval/
   ├── .github/
   │   └── workflows/
   │       ├── ci.yml                # 项目 CI（引用共享可复用工作流）
   │       ├── cd.yml                # 项目 CD（K8s 就绪后启用）
   │       ├── pr-checks.yml         # PR 检查
   │       └── release.yml           # Release
   ├── ci/
   │   ├── k8s/                      # 项目 K8s 配置（保留在项目中，K8s 就绪后启用）
   │   └── config/                   # 项目环境配置（保留在项目中）
   ├── docker/                       # 项目 Dockerfile（保留在项目中）
   └── ...
   ```

### 决策 2：分支策略

| 分支 | 数量 | 触发动作 | 说明 |
|------|------|---------|------|
| `feature/*` | 多个 | 编译 + 测试 | 每个功能独立分支，开发完提 PR 合并到 develop |
| `develop` | 1个 | 编译 + 测试 + 安全扫描 + 构建镜像 + 部署到 dev | 测试环境 |
| `release/*` | 可多个 | 编译 + 测试 + 安全扫描 + 构建镜像 + 部署到 staging | 发版准备分支，如 `release/v1.0`、`release/v1.1` |
| `v*` 标签 | — | 构建镜像 + 创建 Release + 部署到 prod（需审批） | 正式上线 |

日常工作流：
```
1. 开发新功能 → 从 develop 创建 feature/xxx → 推送自动触发编译测试
2. 功能完成 → 提 PR 合并到 develop → 自动部署到 dev 环境
3. 准备发版 → 从 develop 创建 release/v1.0 → 自动部署到 staging 环境
4. 验证通过 → 打标签 v1.0.0 → 部署到 prod（需审批）
5. 发版完成 → release 分支合并回 develop（同步 bug 修复）
```

### 决策 3：分阶段实施

**阶段 0（前置）**：本地 K8s 集群搭建
- 使用 Kind（Kubernetes in Docker）在本地搭建 K8s 集群
- 包含完整的集群配置、Ingress 控制器、本地镜像加载
- 提供一键创建/销毁脚本
- 验证 K8s 集群可用后，CI/CD 流水线的部署功能即可对接

**第一阶段（当前）**：CI 流水线 — 编译、测试、安全扫描、Docker 镜像构建推送
- 不依赖 K8s 集群，只需 GitHub 即可运行
- 镜像推送到 ghcr.io 容器仓库
- K8s 部署步骤预留，条件跳过

**第二阶段（K8s 就绪后）**：CD 部署流水线
- 配置 `KUBE_CONFIG` Secret（从本地 Kind 集群导出）
- 启用 deploy-k8s.yml 和 cd.yml 中的部署步骤
- 启用自动部署到 dev/staging/prod 环境
- 后续迁移到云上 K8s 时，只需更换 KUBE_CONFIG

### 跨仓库引用方式
业务项目通过 `uses: <org>/cicd/.github/workflows/build-java.yml@main` 引用共享工作流。

## What Changes
- 在共享 CI/CD 仓库中创建 4 个可复用工作流（build-java.yml、build-docker.yml、deploy-k8s.yml、security-scan.yml）
- 将 eval 项目的 `ci/scripts/` 中的通用脚本迁移到共享仓库并优化
- 在 eval 项目中创建 4 个项目专属主工作流（ci.yml、cd.yml、pr-checks.yml、release.yml），通过跨仓库 `uses:` 引用共享工作流
- 优化 eval 项目的 Dockerfile 为多阶段构建
- 补充 eval 项目的 Gateway K8s 部署配置（预留，K8s 就绪后使用）
- 增强构建脚本以支持 CI 环境
- CD 工作流中 K8s 部署步骤设为条件执行（K8s 就绪前跳过）

## Impact
- Affected repos:
  - `cicd` 共享仓库（新建可复用工作流和共享脚本）
  - `eval` 业务仓库（新建项目工作流、优化 Dockerfile、补充 K8s 配置）
- Affected code in eval:
  - `.github/workflows/` (新建 ci.yml、cd.yml、pr-checks.yml、release.yml)
  - `docker/Dockerfile.backend` (优化为多阶段构建)
  - `docker/Dockerfile.evaluation` (优化为多阶段构建)
  - `docker/Dockerfile.gateway` (优化为多阶段构建)
  - `ci/k8s/base/` (补充 gateway 部署资源)
  - `ci/k8s/base/kustomization.yaml` (添加 gateway 资源引用)
  - `ci/scripts/build.sh` (增强 CI 环境适配)

## ADDED Requirements

### Requirement: 本地 K8s 集群搭建（Kind）
系统 SHALL 提供基于 Kind 的本地 K8s 集群搭建方案，使用户无需 K8s 经验即可完成集群创建和配置。

#### Scenario: 一键创建本地 K8s 集群
- **WHEN** 用户运行集群创建脚本
- **THEN** 脚本 SHALL 自动完成以下操作：
  - 检查 Docker 是否已安装并运行
  - 安装 Kind（如未安装）
  - 安装 kubectl（如未安装）
  - 使用 Kind 配置文件创建单节点 K8s 集群
  - 安装 Nginx Ingress 控制器
  - 创建 eval 命名空间
  - 输出集群状态和连接信息

#### Scenario: 本地镜像加载到 Kind 集群
- **WHEN** 用户在本地构建了 Docker 镜像
- **THEN** 可通过 `kind load docker-image` 命令将镜像加载到集群中
- **AND** 提供便捷脚本一键加载所有 eval 服务镜像

#### Scenario: 一键销毁集群
- **WHEN** 用户运行集群销毁脚本
- **THEN** 脚本 SHALL 删除 Kind 集群及其所有资源

#### Scenario: 导出 KUBE_CONFIG
- **WHEN** 集群创建成功后
- **THEN** 脚本 SHALL 自动导出 kubeconfig 到 `~/.kube/config`
- **AND** 输出 base64 编码的 kubeconfig（供 GitHub Secrets 使用）

#### Scenario: 集群健康验证
- **WHEN** 集群创建完成
- **THEN** 脚本 SHALL 验证：
  - 节点状态为 Ready
  - Ingress 控制器运行正常
  - kubectl 可以正常连接

### Requirement: 可重用 Java 构建工作流 (build-java.yml)
共享 CI/CD 仓库 SHALL 提供一个可重用的 GitHub Actions 工作流，用于构建 Java Maven 模块，供所有 Java 项目跨仓库引用。

#### Scenario: 成功构建 Java 模块
- **WHEN** 调用方通过 `workflow_call` 触发构建，传入 `java-version`、`maven-modules` 参数
- **THEN** 工作流 SHALL 在 ubuntu-latest runner 上执行 Maven 编译、单元测试和打包
- **AND** 使用 `actions/setup-java@v4` 配置 JDK 并启用 Maven 缓存
- **AND** 构建产物（JAR 文件）通过 `actions/upload-artifact@v4` 上传为工作流产物

#### Scenario: 构建失败
- **WHEN** Maven 编译或测试失败
- **THEN** 工作流 SHALL 标记为失败，并上传测试报告作为产物

#### Scenario: 跨仓库引用
- **WHEN** 业务项目通过 `uses: <org>/cicd/.github/workflows/build-java.yml@v1` 引用
- **THEN** 工作流 SHALL 正确执行，且调用方可通过 `secrets: inherit` 或显式传参使用

### Requirement: 可重用 Docker 构建推送工作流 (build-docker.yml)
共享 CI/CD 仓库 SHALL 提供一个可重用的 GitHub Actions 工作流，用于构建 Docker 镜像并推送到容器仓库。

#### Scenario: 成功构建并推送镜像
- **WHEN** 调用方传入 `image-name`、`dockerfile-path` 参数
- **THEN** 工作流 SHALL 使用 `docker/build-push-action@v5` 构建镜像
- **AND** 为镜像打上 `git SHA` 和 `latest` 两个标签
- **AND** 启用 GitHub Actions 缓存（`cache-from: type=gha`）
- **AND** 推送到 `ghcr.io` 或调用方指定的容器仓库

#### Scenario: 下载构建产物后构建镜像
- **WHEN** 调用方指定 `download-artifact-name` 参数
- **THEN** 工作流 SHALL 先通过 `actions/download-artifact@v4` 下载构建产物
- **AND** 基于下载的产物构建 Docker 镜像

### Requirement: 可重用 K8s 部署工作流 (deploy-k8s.yml)
共享 CI/CD 仓库 SHALL 提供一个可重用的 GitHub Actions 工作流，用于将应用部署到 Kubernetes 集群。此工作流在 K8s 集群就绪后启用。

#### Scenario: 成功部署到指定环境
- **WHEN** 调用方传入 `environment`、`image-tag`、`kustomize-overlay-path` 参数
- **THEN** 工作流 SHALL 使用 Kustomize 构建对应环境的清单
- **AND** 通过 `kubectl apply` 部署到目标集群
- **AND** 等待 rollout 完成并验证部署状态
- **AND** 部署完成后执行健康检查

#### Scenario: 部署失败自动回滚
- **WHEN** 部署后健康检查失败
- **THEN** 工作流 SHALL 自动执行 `kubectl rollout undo` 回滚到上一版本
- **AND** 发送部署失败通知

#### Scenario: K8s 未就绪时跳过部署
- **WHEN** `KUBE_CONFIG` Secret 未配置
- **THEN** 部署步骤 SHALL 被跳过，CI 流水线其余部分正常完成

### Requirement: 可重用安全扫描工作流 (security-scan.yml)
共享 CI/CD 仓库 SHALL 提供一个可重用的 GitHub Actions 工作流，用于执行代码和依赖安全扫描。

#### Scenario: 执行安全扫描
- **WHEN** 工作流被触发
- **THEN** SHALL 执行以下扫描：
  - Maven 依赖漏洞扫描（`org.owasp:dependency-check-maven`）
  - 容器镜像漏洞扫描（`aquasecurity/trivy-action`）
  - 代码静态分析（`github/codeql-action`）
- **AND** 扫描结果上传到 GitHub Security 选项卡
- **AND** 发现高危漏洞时工作流 SHALL 失败

### Requirement: Eval 项目 CI 主工作流 (ci.yml)
Eval 项目 SHALL 提供持续集成主工作流，在代码推送时自动触发，通过跨仓库引用调用共享可复用工作流。

#### Scenario: 推送到 feature 分支
- **WHEN** 代码推送到 `feature/**` 分支
- **THEN** 触发后端构建 + 测试、前端构建 + 类型检查
- **AND** 使用 `concurrency` 组确保同一分支只运行最新一次

#### Scenario: 推送到 develop 分支
- **WHEN** 代码推送到 `develop` 分支
- **THEN** 触发完整的 CI 流水线：构建、测试、安全扫描、Docker 镜像构建推送
- **AND** 如果 K8s 已就绪，构建成功后自动部署到 dev 环境

#### Scenario: 推送到 release 分支
- **WHEN** 代码推送到 `release/**` 分支
- **THEN** 触发完整的 CI 流水线：构建、测试、安全扫描、Docker 镜像构建推送
- **AND** 如果 K8s 已就绪，构建成功后自动部署到 staging 环境

#### Scenario: 跨仓库引用共享工作流
- **WHEN** CI 工作流需要执行 Java 构建
- **THEN** SHALL 通过 `uses: <org>/cicd/.github/workflows/build-java.yml@v1` 引用共享工作流
- **AND** 传入 eval 项目特定的参数（maven-modules、java-version 等）

### Requirement: Eval 项目 CD 主工作流 (cd.yml)
Eval 项目 SHALL 提供持续部署主工作流，支持手动和自动触发部署。K8s 集群就绪前，部署步骤条件跳过。

#### Scenario: 手动触发部署
- **WHEN** 通过 `workflow_dispatch` 手动触发，选择目标环境
- **THEN** 工作流 SHALL 部署指定镜像版本到目标环境
- **AND** 生产环境部署需要审批（`environment: prod` 配置审批人）

#### Scenario: 基于标签的自动部署
- **WHEN** 推送 `v*` 格式的标签
- **THEN** 工作流 SHALL 自动触发生产环境部署流程
- **AND** 需要审批后才能执行

#### Scenario: K8s 未就绪
- **WHEN** `KUBE_CONFIG` Secret 未配置
- **THEN** 部署步骤 SHALL 被跳过，仅执行镜像构建推送

### Requirement: Eval 项目 PR 检查工作流 (pr-checks.yml)
Eval 项目 SHALL 提供 PR 检查工作流，在 Pull Request 时自动执行质量门禁。

#### Scenario: 创建或更新 PR 到 develop
- **WHEN** 向 `develop` 分支创建/更新 PR
- **THEN** 工作流 SHALL 执行：
  - 后端编译 + 单元测试
  - 前端类型检查 + Lint
  - 代码格式检查
- **AND** 所有检查通过后 PR 才允许合并

#### Scenario: 创建或更新 PR 到 release 分支
- **WHEN** 向 `release/**` 分支创建/更新 PR
- **THEN** 工作流 SHALL 执行与 develop PR 相同的检查

### Requirement: Eval 项目 Release 工作流 (release.yml)
Eval 项目 SHALL 提供 Release 工作流，用于创建正式发布版本。

#### Scenario: 创建 Release
- **WHEN** 推送 `v*` 格式标签
- **THEN** 工作流 SHALL：
  - 构建所有服务的 Docker 镜像
  - 为镜像打上语义化版本标签
  - 创建 GitHub Release
  - 如果 K8s 已就绪，触发生产环境部署

### Requirement: Dockerfile 多阶段构建优化
Eval 项目的 Dockerfile SHALL 优化为多阶段构建，支持 CI 环境下从源码直接构建。

#### Scenario: CI 环境构建
- **WHEN** 在 GitHub Actions 中构建镜像
- **THEN** Dockerfile SHALL 包含构建阶段（Maven 编译）和运行阶段（JRE 运行）
- **AND** 构建阶段使用 `eclipse-temurin:21-jdk` 基础镜像
- **AND** 运行阶段使用 `eclipse-temurin:21-jre-alpine` 基础镜像
- **AND** 利用 Docker 层缓存优化 Maven 依赖下载

#### Scenario: 本地开发构建
- **WHEN** 本地使用 `docker build` 构建镜像
- **THEN** 同样使用多阶段构建，无需预先执行 `mvn package`

### Requirement: Gateway K8s 部署配置
Eval 项目 SHALL 补充 Gateway 服务的 Kubernetes 部署资源（K8s 就绪后使用）。

#### Scenario: 部署 Gateway 到 K8s
- **WHEN** 执行 Kustomize 部署
- **THEN** SHALL 包含 Gateway 的 Deployment 和 Service 资源
- **AND** Gateway 暴露 9090 端口
- **AND** Ingress 配置包含 Gateway 路由规则

### Requirement: 通知集成
系统 SHALL 在 CI/CD 关键事件发生时发送通知。

#### Scenario: 构建或部署状态变更
- **WHEN** 构建失败、部署成功/失败、安全漏洞发现等事件发生
- **THEN** 工作流 SHALL 通过 GitHub Commit Status 标记状态
- **AND** 可选发送 Slack/钉钉通知（通过配置的 Webhook URL）

### Requirement: 共享脚本迁移与优化
Eval 项目的 `ci/scripts/` 中的通用脚本 SHALL 迁移到共享 CI/CD 仓库，并优化为通用版本。

#### Scenario: 脚本迁移
- **WHEN** 共享 CI/CD 仓库建立
- **THEN** 以下脚本 SHALL 迁移到共享仓库：
  - `build.sh` → 通用 Docker 构建脚本
  - `deploy.sh` → 通用 K8s 部署脚本
  - `health-check.sh` → 通用健康检查脚本
  - `notify.sh` → 通用通知脚本
  - `rollback.sh` → 通用回滚脚本
- **AND** 脚本 SHALL 通过环境变量参数化，不硬编码项目名
- **AND** Eval 项目保留 `ci/scripts/` 作为项目特有脚本的存放位置

## MODIFIED Requirements

### Requirement: 现有构建脚本增强
现有 `ci/scripts/build.sh` SHALL 增加对 CI 环境的适配：
- 支持 `GITHUB_SHA` 环境变量作为默认镜像标签
- 支持 `DOCKER_REGISTRY` 环境变量覆盖默认仓库地址
- 增加构建耗时统计和构建结果摘要输出
- 增加 gateway 镜像构建支持

### Requirement: 现有 Kustomize 配置更新
现有 `ci/k8s/base/kustomization.yaml` SHALL 更新：
- 添加 Gateway 相关资源引用
- 镜像地址占位符保持可配置（通过 overlay 替换）

### Requirement: 分支策略从 main 改为 release/*
原有设计使用 `main` 分支作为稳定版分支，现修改为使用 `release/*` 分支模式：
- `develop` → `release/*` → `v*` 标签
- PR 目标分支从 `main` 改为 `develop` 和 `release/*`
- CI 触发条件从 `main` 改为 `release/**`
