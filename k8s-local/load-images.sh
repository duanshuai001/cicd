#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# eval 服务镜像构建与加载脚本
# 构建 Docker 镜像并加载到 Kind 集群中
# 用法: ./load-images.sh [IMAGE_TAG]
# ============================================================

CLUSTER_NAME="eval-dev"
IMAGE_TAG="${1:-latest}"
EVAL_ROOT="/Users/duanshuai/mycode/eval"
DOCKER_DIR="${EVAL_ROOT}/docker"

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

# 服务定义: 名称=Dockerfile名称
SERVICES=(
  "backend=Dockerfile.backend"
  "evaluation=Dockerfile.evaluation"
  "gateway=Dockerfile.gateway"
  "frontend=Dockerfile.frontend"
)

# ----------------------------------------------------------
# 检查前置条件
# ----------------------------------------------------------
check_prerequisites() {
  info "检查前置条件..."

  if ! command -v docker &>/dev/null; then
    error "Docker 未安装"
  fi

  if ! command -v kind &>/dev/null; then
    error "Kind 未安装，请先运行 create-cluster.sh"
  fi

  if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    error "集群 ${CLUSTER_NAME} 不存在，请先运行 create-cluster.sh"
  fi

  if [ ! -d "${DOCKER_DIR}" ]; then
    error "Docker 目录不存在: ${DOCKER_DIR}"
  fi

  success "前置条件检查通过"
}

# ----------------------------------------------------------
# 构建并加载单个服务镜像
# ----------------------------------------------------------
build_and_load() {
  local service_name="$1"
  local dockerfile="$2"
  local image_name="eval/${service_name}:${IMAGE_TAG}"
  local dockerfile_path="${DOCKER_DIR}/${dockerfile}"

  if [ ! -f "${dockerfile_path}" ]; then
    error "Dockerfile 不存在: ${dockerfile_path}"
  fi

  echo ""
  info "构建镜像: ${image_name}"
  info "Dockerfile: ${dockerfile_path}"
  info "构建上下文: ${EVAL_ROOT}"

  docker build \
    -t "${image_name}" \
    -f "${dockerfile_path}" \
    "${EVAL_ROOT}"

  success "镜像构建完成: ${image_name}"

  info "加载镜像到集群 ${CLUSTER_NAME}..."
  kind load docker-image "${image_name}" --name "${CLUSTER_NAME}"
  success "镜像已加载到集群: ${image_name}"
}

# ----------------------------------------------------------
# 主流程
# ----------------------------------------------------------
main() {
  echo -e "${BLUE}============================================================${NC}"
  echo -e "${BLUE}  eval 服务镜像构建与加载${NC}"
  echo -e "${BLUE}  镜像标签: ${IMAGE_TAG}${NC}"
  echo -e "${BLUE}============================================================${NC}"
  echo ""

  check_prerequisites

  for service_def in "${SERVICES[@]}"; do
    local service_name="${service_def%%=*}"
    local dockerfile="${service_def##*=}"
    build_and_load "${service_name}" "${dockerfile}"
  done

  echo ""
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${GREEN}  所有镜像构建并加载完成！${NC}"
  echo -e "${GREEN}  镜像标签: ${IMAGE_TAG}${NC}"
  echo -e "${GREEN}  下一步: 运行 verify-deployment.sh 部署并验证${NC}"
  echo -e "${GREEN}============================================================${NC}"

  echo ""
  info "已加载的镜像列表:"
  docker exec -it "${CLUSTER_NAME}-control-plane" crictl images | grep "eval/" || true
}

main "$@"
