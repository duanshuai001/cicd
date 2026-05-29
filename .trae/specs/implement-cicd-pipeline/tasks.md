# Tasks

## 阶段 0：本地 K8s 集群搭建

- [x] Task 0: 搭建本地 Kind K8s 集群
  - [x] SubTask 0.1: 创建 Kind 集群配置文件 `cicd/k8s-local/kind-config.yaml`（单节点集群 + Ingress 端口映射 + 本地 Docker 网络）
  - [x] SubTask 0.2: 创建一键创建集群脚本 `cicd/k8s-local/create-cluster.sh`（检查 Docker → 安装 Kind/kubectl → 创建集群 → 安装 Ingress 控制器 → 创建命名空间 → 导出 kubeconfig → 健康验证）
  - [x] SubTask 0.3: 创建一键销毁集群脚本 `cicd/k8s-local/destroy-cluster.sh`
  - [x] SubTask 0.4: 创建本地镜像加载脚本 `cicd/k8s-local/load-images.sh`（构建 eval 所有服务镜像并加载到 Kind 集群）
  - [x] SubTask 0.5: 创建本地部署验证脚本 `cicd/k8s-local/verify-deployment.sh`（部署 eval 应用到本地 Kind 集群并验证服务可达）
  - [ ] SubTask 0.6: 实际执行创建集群脚本，验证集群可用

## 阶段一：共享 CI/CD 仓库建设（cicd 仓库）

- [x] Task 1: 创建可重用工作流 - build-java.yml（共享仓库）
  - [x] SubTask 1.1: 创建 `cicd/.github/workflows/build-java.yml`，定义 `workflow_call` 触发器和输入参数（java-version, maven-modules, run-integration-tests）
  - [x] SubTask 1.2: 配置 JDK 21 + Maven 缓存步骤（`actions/setup-java@v4`，cache: maven）
  - [x] SubTask 1.3: 实现 Maven 编译 → 单元测试 → 集成测试（可选）→ 打包的 job 流程
  - [x] SubTask 1.4: 添加 `actions/upload-artifact@v4` 上传构建产物（JAR 文件和测试报告）

- [x] Task 2: 创建可重用工作流 - build-docker.yml（共享仓库）
  - [x] SubTask 2.1: 创建 `cicd/.github/workflows/build-docker.yml`，定义输入参数（image-name, dockerfile-path, docker-context, download-artifact-name）
  - [x] SubTask 2.2: 配置 Docker 登录（`docker/login-action@v3`，支持 ghcr.io 和自定义仓库）
  - [x] SubTask 2.3: 实现可选的构建产物下载步骤（`actions/download-artifact@v4`）
  - [x] SubTask 2.4: 实现镜像构建和推送（`docker/build-push-action@v5`，GHA 缓存，SHA + latest 双标签）
  - [x] SubTask 2.5: 输出镜像完整标签供下游工作流使用

- [x] Task 3: 创建可重用工作流 - deploy-k8s.yml（共享仓库，K8s 就绪后启用）
  - [x] SubTask 3.1: 创建 `cicd/.github/workflows/deploy-k8s.yml`，定义输入参数（environment, image-tag, namespace, kustomize-overlay-path）和 secrets（KUBE_CONFIG）
  - [x] SubTask 3.2: 配置 kubectl + kustomize 工具安装
  - [x] SubTask 3.3: 实现 Kustomize 构建 → kubectl apply → rollout status 等待流程
  - [x] SubTask 3.4: 添加部署后健康检查步骤
  - [x] SubTask 3.5: 实现部署失败自动回滚逻辑
  - [x] SubTask 3.6: 添加 KUBE_CONFIG 是否存在的条件判断，未配置时跳过部署

- [x] Task 4: 创建可重用工作流 - security-scan.yml（共享仓库）
  - [x] SubTask 4.1: 创建 `cicd/.github/workflows/security-scan.yml`，定义输入参数（java-version, maven-modules, image-name）
  - [x] SubTask 4.2: 集成 OWASP Dependency Check 扫描 Maven 依赖漏洞
  - [x] SubTask 4.3: 集成 Trivy 容器镜像漏洞扫描
  - [x] SubTask 4.4: 集成 CodeQL 代码静态分析
  - [x] SubTask 4.5: 配置扫描结果上传到 GitHub Security 选项卡

- [x] Task 5: 迁移和优化共享脚本（共享仓库）
  - [x] SubTask 5.1: 将 eval 项目的 `ci/scripts/build.sh` 迁移到 `cicd/scripts/build.sh`，参数化项目名和服务列表
  - [x] SubTask 5.2: 将 `deploy.sh` 迁移并参数化（环境变量驱动，不硬编码项目名）
  - [x] SubTask 5.3: 将 `health-check.sh` 迁移并参数化
  - [x] SubTask 5.4: 将 `notify.sh` 迁移并参数化
  - [x] SubTask 5.5: 将 `rollback.sh` 迁移并参数化
  - [x] SubTask 5.6: 迁移配置模板 `environments.yml` 和 `notifications.yml` 到 `cicd/config/`

## 阶段二：Eval 项目工作流建设（eval 仓库）

- [x] Task 6: 创建 Eval 项目 CI 主工作流 - ci.yml
  - [x] SubTask 6.1: 创建 `eval/.github/workflows/ci.yml`，配置触发条件（push to develop/release/**/feature/**，PR to develop/release/**）
  - [x] SubTask 6.2: 配置 concurrency 组（同一分支取消旧运行）
  - [x] SubTask 6.3: 实现后端构建 job（跨仓库引用 `uses: <org>/cicd/.github/workflows/build-java.yml@v1`，传入 eval-monolith/eval-starter 模块）
  - [x] SubTask 6.4: 实现 Evaluation 服务构建 job（引用 build-java.yml，传入 eval-evaluation/eval-evaluation-starter 模块）
  - [x] SubTask 6.5: 实现前端构建 job（Node.js 20 + npm ci + vue-tsc + build，内联步骤）
  - [x] SubTask 6.6: 实现 Docker 镜像构建 job（依赖构建 job，引用 build-docker.yml 构建 backend/frontend/evaluation/gateway 四个镜像），仅 develop 和 release/** 分支触发
  - [x] SubTask 6.7: 实现安全扫描 job（引用 security-scan.yml），仅 develop 和 release/** 分支触发
  - [x] SubTask 6.8: 实现 dev 环境自动部署 job（develop 分支触发时，引用 deploy-k8s.yml），K8s 就绪前条件跳过
  - [x] SubTask 6.9: 实现 staging 环境自动部署 job（release/** 分支触发时，引用 deploy-k8s.yml），K8s 就绪前条件跳过

- [x] Task 7: 创建 Eval 项目 CD 主工作流 - cd.yml
  - [x] SubTask 7.1: 创建 `eval/.github/workflows/cd.yml`，配置触发条件（workflow_dispatch, tag v*）
  - [x] SubTask 7.2: 实现 staging 部署 job（手动触发时，引用 deploy-k8s.yml）
  - [x] SubTask 7.3: 实现 prod 部署 job（v* 标签触发，需审批，引用 deploy-k8s.yml）
  - [x] SubTask 7.4: 实现手动部署选项（workflow_dispatch 支持 dev/staging/prod 选择）
  - [x] SubTask 7.5: 添加部署通知步骤
  - [x] SubTask 7.6: 所有部署步骤添加 K8s 就绪条件判断

- [x] Task 8: 创建 Eval 项目 PR 检查工作流 - pr-checks.yml
  - [x] SubTask 8.1: 创建 `eval/.github/workflows/pr-checks.yml`，配置触发条件（PR to develop/release/**）
  - [x] SubTask 8.2: 实现后端编译 + 单元测试 job（快速模式，仅 compile + test）
  - [x] SubTask 8.3: 实现前端类型检查 + Lint job
  - [x] SubTask 8.4: 实现代码格式检查 job（可选）

- [x] Task 9: 创建 Eval 项目 Release 工作流 - release.yml
  - [x] SubTask 9.1: 创建 `eval/.github/workflows/release.yml`，配置触发条件（tag v*）
  - [x] SubTask 9.2: 实现全量构建 + Docker 镜像构建（引用 build-java.yml 和 build-docker.yml）
  - [x] SubTask 9.3: 实现语义化版本标签（从 git tag 提取版本号）
  - [x] SubTask 9.4: 实现创建 GitHub Release 步骤（自动生成 changelog）
  - [x] SubTask 9.5: 触发生产环境部署（引用 deploy-k8s.yml），K8s 就绪前条件跳过

## 阶段三：Eval 项目基础设施优化（eval 仓库）

- [x] Task 10: 优化 Dockerfile 为多阶段构建
  - [x] SubTask 10.1: 优化 `docker/Dockerfile.backend` 为多阶段构建（Maven 构建阶段 + JRE 运行阶段）
  - [x] SubTask 10.2: 优化 `docker/Dockerfile.evaluation` 为多阶段构建
  - [x] SubTask 10.3: 优化 `docker/Dockerfile.gateway` 为多阶段构建
  - [x] SubTask 10.4: 确保 Dockerfile 同时兼容 CI 环境和本地 `docker build`

- [x] Task 11: 补充 Gateway K8s 部署配置
  - [x] SubTask 11.1: 创建 `ci/k8s/base/gateway-deployment.yaml`
  - [x] SubTask 11.2: 创建 `ci/k8s/base/gateway-service.yaml`
  - [x] SubTask 11.3: 更新 `ci/k8s/base/kustomization.yaml` 添加 gateway 资源
  - [x] SubTask 11.4: 更新 `ci/k8s/base/ingress.yaml` 添加 gateway 路由
  - [x] SubTask 11.5: 更新各 overlay 的 kustomization.yaml 适配 gateway 配置

- [x] Task 12: 增强构建脚本
  - [x] SubTask 12.1: 更新 `ci/scripts/build.sh` 支持 `GITHUB_SHA` 作为默认镜像标签
  - [x] SubTask 12.2: 添加构建耗时统计和构建结果摘要输出
  - [x] SubTask 12.3: 增加 gateway 镜像构建支持

# Task Dependencies
- [Task 0] 独立，应最先执行（K8s 集群是后续部署的基础）
- [Task 6] depends on [Task 1, Task 2, Task 3, Task 4] (Eval CI 工作流跨仓库引用共享可复用工作流)
- [Task 7] depends on [Task 3, Task 0] (Eval CD 工作流引用 deploy-k8s.yml，且需要 K8s 集群)
- [Task 9] depends on [Task 1, Task 2, Task 3] (Release 工作流引用构建和部署可重用工作流)
- [Task 10] 独立，可与阶段一并行
- [Task 11] depends on [Task 0] (K8s 配置需要集群来验证)
- [Task 12] 独立，可与阶段一并行
- [Task 5] 独立，可与 Task 1-4 并行
- [Task 8] 独立，可与 Task 1-4 并行（PR 检查不依赖共享工作流，使用内联步骤）
