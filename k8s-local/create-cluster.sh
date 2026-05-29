#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# eval-dev Kind 集群一键创建脚本
# 用于本地开发环境搭建，包含 Ingress 控制器和命名空间配置
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="eval-dev"
KUBECONFIG_DIR="${HOME}/.kube"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ----------------------------------------------------------
# 检查 Docker 是否安装并运行
# ----------------------------------------------------------
check_docker() {
  info "检查 Docker 是否安装..."
  if ! command -v docker &>/dev/null; then
    error "Docker 未安装，请先安装 Docker Desktop: https://docs.docker.com/desktop/install/mac-install/"
  fi
  success "Docker 已安装: $(docker --version)"

  info "检查 Docker 是否运行..."
  if ! docker info &>/dev/null; then
    error "Docker 未运行，请先启动 Docker Desktop"
  fi
  success "Docker 正在运行"
}

# ----------------------------------------------------------
# 安装 Kind（macOS 通过 brew）
# ----------------------------------------------------------
install_kind() {
  if command -v kind &>/dev/null; then
    success "Kind 已安装: $(kind version)"
    return
  fi

  info "Kind 未安装，正在通过 brew 安装..."
  if ! command -v brew &>/dev/null; then
    error "Homebrew 未安装，请先安装: https://brew.sh/"
  fi
  brew install kind
  success "Kind 安装完成: $(kind version)"
}

# ----------------------------------------------------------
# 安装 kubectl
# ----------------------------------------------------------
install_kubectl() {
  if command -v kubectl &>/dev/null; then
    success "kubectl 已安装: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
    return
  fi

  info "kubectl 未安装，正在通过 brew 安装..."
  if ! command -v brew &>/dev/null; then
    error "Homebrew 未安装，请先安装: https://brew.sh/"
  fi
  brew install kubectl
  success "kubectl 安装完成: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
}

# ----------------------------------------------------------
# 创建 Kind 集群
# ----------------------------------------------------------
create_cluster() {
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    warn "集群 ${CLUSTER_NAME} 已存在，跳过创建"
    return
  fi

  info "正在创建 Kind 集群 ${CLUSTER_NAME}..."
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --config "${SCRIPT_DIR}/kind-config.yaml" \
    --wait 120s
  success "集群 ${CLUSTER_NAME} 创建完成"
}

# ----------------------------------------------------------
# 安装 Nginx Ingress Controller
# ----------------------------------------------------------
install_ingress() {
  info "正在安装 Nginx Ingress Controller..."
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

  info "等待 Ingress Controller 就绪..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s
  success "Nginx Ingress Controller 安装完成并已就绪"
}

# ----------------------------------------------------------
# 创建 eval 命名空间
# ----------------------------------------------------------
create_namespace() {
  info "创建 eval 命名空间..."
  if kubectl get namespace eval &>/dev/null 2>&1; then
    warn "命名空间 eval 已存在，跳过创建"
  else
    kubectl create namespace eval
    success "命名空间 eval 创建完成"
  fi
}

# ----------------------------------------------------------
# 导出 kubeconfig
# ----------------------------------------------------------
export_kubeconfig() {
  info "导出 kubeconfig 到 ${KUBECONFIG_DIR}/config..."
  mkdir -p "${KUBECONFIG_DIR}"

  local kubeconfig_content
  kubeconfig_content="$(kind get kubeconfig --name "${CLUSTER_NAME}")"

  if [ -f "${KUBECONFIG_DIR}/config" ]; then
    # 合并 kubeconfig：将 eval-dev 的配置合并到现有配置中
    local tmp_file
    tmp_file="$(mktemp)"
    echo "${kubeconfig_content}" > "${tmp_file}"

    # 备份现有配置
    cp "${KUBECONFIG_DIR}/config" "${KUBECONFIG_DIR}/config.bak.$(date +%Y%m%d%H%M%S)"

    # 使用 KUBECONFIG 环境变量合并
    KUBECONFIG="${KUBECONFIG_DIR}/config:${tmp_file}" kubectl config view --flatten > "${KUBECONFIG_DIR}/config.merged"
    mv "${KUBECONFIG_DIR}/config.merged" "${KUBECONFIG_DIR}/config"
    rm -f "${tmp_file}"

    success "kubeconfig 已合并到 ${KUBECONFIG_DIR}/config"
  else
    echo "${kubeconfig_content}" > "${KUBECONFIG_DIR}/config"
    chmod 600 "${KUBECONFIG_DIR}/config"
    success "kubeconfig 已写入 ${KUBECONFIG_DIR}/config"
  fi

  # 切换当前上下文到 eval-dev
  kubectl config use-context "kind-${CLUSTER_NAME}" 2>/dev/null || true
  success "已切换上下文到 kind-${CLUSTER_NAME}"
}

# ----------------------------------------------------------
# 输出 base64 编码的 kubeconfig（用于 GitHub Secrets）
# ----------------------------------------------------------
print_kubeconfig_base64() {
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  GitHub Secrets 所需的 base64 编码 kubeconfig${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo ""
  kind get kubeconfig --name "${CLUSTER_NAME}" | base64
  echo ""
  info "将上述 base64 字符串添加到 GitHub 仓库的 Secrets 中（名称: KUBECONFIG）"
  echo ""
}

# ----------------------------------------------------------
# 健康检查验证
# ----------------------------------------------------------
health_check() {
  info "正在执行健康检查..."

  echo ""
  info "1. 检查节点状态..."
  local node_ready
  node_ready="$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')"
  if [ "${node_ready}" = "True" ]; then
    success "节点状态: Ready"
    kubectl get nodes
  else
    error "节点状态异常: ${node_ready}"
  fi

  echo ""
  info "2. 检查 Ingress Controller..."
  local ingress_pods
  ingress_pods="$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${ingress_pods}" -gt 0 ]; then
    success "Ingress Controller 运行中 (${ingress_pods} pod(s))"
    kubectl get pods -n ingress-nginx
  else
    error "Ingress Controller 未运行"
  fi

  echo ""
  info "3. 检查 kubectl 连通性..."
  if kubectl cluster-info &>/dev/null; then
    success "kubectl 连接集群正常"
    kubectl cluster-info
  else
    error "kubectl 无法连接集群"
  fi

  echo ""
  success "所有健康检查通过！集群 ${CLUSTER_NAME} 已就绪"
}

# ----------------------------------------------------------
# 主流程
# ----------------------------------------------------------
main() {
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  eval-dev Kind 集群一键创建${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo ""

  check_docker
  install_kind
  install_kubectl
  create_cluster
  install_ingress
  create_namespace
  export_kubeconfig
  print_kubeconfig_base64
  health_check

  echo ""
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${GREEN}  集群创建完成！${NC}"
  echo -e "${GREEN}  - 集群名称: ${CLUSTER_NAME}${NC}"
  echo -e "${GREEN}  - 命名空间: eval${NC}"
  echo -e "${GREEN}  - Ingress:  Nginx (端口 80/443)${NC}"
  echo -e "${GREEN}  - 下一步:   运行 load-images.sh 加载镜像${NC}"
  echo -e "${GREEN}============================================================${NC}"
}

main "$@"
