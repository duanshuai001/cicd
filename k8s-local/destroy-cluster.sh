#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# eval-dev Kind 集群一键销毁脚本
# 删除集群并清理 kubeconfig 中的相关配置
# ============================================================

CLUSTER_NAME="eval-dev"
KUBECONFIG_FILE="${HOME}/.kube/config"

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
# 删除 Kind 集群
# ----------------------------------------------------------
delete_cluster() {
  info "正在删除 Kind 集群 ${CLUSTER_NAME}..."

  if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    warn "集群 ${CLUSTER_NAME} 不存在，无需删除"
    return
  fi

  kind delete cluster --name "${CLUSTER_NAME}"
  success "集群 ${CLUSTER_NAME} 已删除"
}

# ----------------------------------------------------------
# 清理 kubeconfig 中的相关引用
# ----------------------------------------------------------
cleanup_kubeconfig() {
  info "清理 kubeconfig 中的 ${CLUSTER_NAME} 相关配置..."

  if [ ! -f "${KUBECONFIG_FILE}" ]; then
    warn "kubeconfig 文件不存在: ${KUBECONFIG_FILE}"
    return
  fi

  # 删除与 kind-eval-dev 相关的 context、cluster、user
  kubectl config delete-context "kind-${CLUSTER_NAME}" 2>/dev/null || true
  kubectl config delete-cluster "kind-${CLUSTER_NAME}" 2>/dev/null || true
  kubectl config unset "users.kind-${CLUSTER_NAME}" 2>/dev/null || true

  success "kubeconfig 清理完成"
}

# ----------------------------------------------------------
# 主流程
# ----------------------------------------------------------
main() {
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  eval-dev Kind 集群一键销毁${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo ""

  delete_cluster
  cleanup_kubeconfig

  echo ""
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${GREEN}  集群销毁完成！${NC}"
  echo -e "${GREEN}============================================================${NC}"
}

main "$@"
