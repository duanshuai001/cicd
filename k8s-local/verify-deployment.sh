#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# eval 部署验证脚本
# 应用 Kustomize 清单并验证所有服务正常运行
# ============================================================

CLUSTER_NAME="eval-dev"
NAMESPACE="eval-dev"
KUSTOMIZE_DIR="/Users/duanshuai/mycode/eval/ci/k8s/overlays/dev"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-300}"

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
# 检查前置条件
# ----------------------------------------------------------
check_prerequisites() {
  info "检查前置条件..."

  if ! command -v kubectl &>/dev/null; then
    error "kubectl 未安装"
  fi

  if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    error "集群 ${CLUSTER_NAME} 不存在，请先运行 create-cluster.sh"
  fi

  if [ ! -f "${KUSTOMIZE_DIR}/kustomization.yaml" ]; then
    error "Kustomize 配置不存在: ${KUSTOMIZE_DIR}/kustomization.yaml"
  fi

  success "前置条件检查通过"
}

# ----------------------------------------------------------
# 应用 Kustomize 清单
# ----------------------------------------------------------
apply_manifests() {
  info "正在应用 Kustomize 清单 (环境: dev)..."
  info "清单目录: ${KUSTOMIZE_DIR}"

  kubectl apply -k "${KUSTOMIZE_DIR}"

  success "Kustomize 清单已应用"
}

# ----------------------------------------------------------
# 等待所有 Deployment 就绪
# ----------------------------------------------------------
wait_for_deployments() {
  info "等待所有 Deployment 就绪 (超时: ${DEPLOY_TIMEOUT}s)..."

  local deployments
  deployments="$(kubectl get deployments -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"

  if [ -z "${deployments}" ]; then
    warn "命名空间 ${NAMESPACE} 中没有找到 Deployment"
    return
  fi

  for deploy in ${deployments}; do
    info "等待 Deployment ${deploy} 就绪..."
    if ! kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout="${DEPLOY_TIMEOUT}s"; then
      error "Deployment ${deploy} 就绪超时"
    fi
    success "Deployment ${deploy} 已就绪"
  done
}

# ----------------------------------------------------------
# 检查 Pod 健康状态
# ----------------------------------------------------------
check_pod_health() {
  echo ""
  info "检查 Pod 健康状态..."

  local pod_count
  pod_count="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"

  if [ "${pod_count}" -eq 0 ]; then
    warn "命名空间 ${NAMESPACE} 中没有运行中的 Pod"
    return
  fi

  local running_count
  running_count="$(kubectl get pods -n "${NAMESPACE}" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')"

  local crash_count
  crash_count="$(kubectl get pods -n "${NAMESPACE}" --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l | tr -d ' ')"

  info "Pod 总数: ${pod_count}, 运行中: ${running_count}, 异常: ${crash_count}"

  if [ "${crash_count}" -gt 0 ]; then
    warn "发现异常 Pod:"
    kubectl get pods -n "${NAMESPACE}" --field-selector=status.phase=Failed
  fi

  echo ""
  info "Pod 详情:"
  kubectl get pods -n "${NAMESPACE}" -o wide

  if [ "${running_count}" -eq "${pod_count}" ]; then
    success "所有 Pod 运行正常"
  else
    warn "部分 Pod 未就绪，请检查事件日志"
  fi
}

# ----------------------------------------------------------
# 验证 Service 端点
# ----------------------------------------------------------
verify_services() {
  echo ""
  info "验证 Service 端点..."

  local services
  services="$(kubectl get services -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"

  if [ -z "${services}" ]; then
    warn "命名空间 ${NAMESPACE} 中没有找到 Service"
    return
  fi

  for svc in ${services}; do
    local svc_type
    svc_type="$(kubectl get svc "${svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.type}' 2>/dev/null)"
    local cluster_ip
    cluster_ip="$(kubectl get svc "${svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)"
    local ports
    ports="$(kubectl get svc "${svc}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[*].port}' 2>/dev/null)"

    if [ "${svc_type}" = "ClusterIP" ] && [ "${cluster_ip}" != "None" ]; then
      success "Service ${svc}: ${cluster_ip} (端口: ${ports})"
    else
      info "Service ${svc}: 类型=${svc_type}, 端口=${ports}"
    fi
  done

  echo ""
  info "Service 列表:"
  kubectl get svc -n "${NAMESPACE}"
}

# ----------------------------------------------------------
# 测试 Ingress HTTP 连通性
# ----------------------------------------------------------
test_ingress() {
  echo ""
  info "测试 Ingress HTTP 连通性..."

  local ingress_list
  ingress_list="$(kubectl get ingress -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"

  if [ -z "${ingress_list}" ]; then
    warn "命名空间 ${NAMESPACE} 中没有找到 Ingress 资源"
    return
  fi

  for ingress in ${ingress_list}; do
    local host
    host="$(kubectl get ingress "${ingress}" -n "${NAMESPACE}" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)"

    info "Ingress: ${ingress} (Host: ${host})"

    # 测试通过 localhost:80 访问（Kind 端口映射）
    local http_code
    http_code="$(curl -s -o /dev/null -w "%{http_code}" \
      --resolve "${host}:80:127.0.0.1" \
      "http://${host}/" \
      --max-time 10 2>/dev/null || echo "000")"

    if [ "${http_code}" = "000" ]; then
      warn "Ingress ${ingress}: 连接超时或拒绝"
    elif [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 400 ]; then
      success "Ingress ${ingress}: HTTP ${http_code} (正常)"
    else
      warn "Ingress ${ingress}: HTTP ${http_code} (服务可能尚未完全启动)"
    fi
  done

  echo ""
  info "Ingress 列表:"
  kubectl get ingress -n "${NAMESPACE}"
}

# ----------------------------------------------------------
# 输出诊断信息（如验证失败可参考）
# ----------------------------------------------------------
print_diagnostics() {
  echo ""
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  诊断信息${NC}"
  echo -e "${BLUE}============================================================${NC}"

  echo ""
  info "最近事件 (命名空间: ${NAMESPACE}):"
  kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true

  echo ""
  info "资源使用情况:"
  kubectl top pods -n "${NAMESPACE}" 2>/dev/null || warn "metrics-server 未安装，无法获取资源使用情况"
}

# ----------------------------------------------------------
# 主流程
# ----------------------------------------------------------
main() {
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  eval 部署验证${NC}"
  echo -e "${BLUE}  命名空间: ${NAMESPACE}${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo ""

  check_prerequisites
  apply_manifests
  wait_for_deployments
  check_pod_health
  verify_services
  test_ingress
  print_diagnostics

  echo ""
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${GREEN}  部署验证完成！${NC}"
  echo -e "${GREEN}  - 集群: ${CLUSTER_NAME}${NC}"
  echo -e "${GREEN}  - 命名空间: ${NAMESPACE}${NC}"
  echo -e "${GREEN}  - 访问方式: 通过 Ingress Host 头访问服务${NC}"
  echo -e "${GREEN}============================================================${NC}"
}

main "$@"
