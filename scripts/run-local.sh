#!/bin/bash
# ============================================================
# 本地启动单个 Spring Boot 服务（带日志大小上限保护）
# 用法: ./run-local.sh <服务名>
#   服务名: eval-boot | eval-answer-boot | perm-boot | basedata-boot | bizgraph-new
#
# 日志保护: 每个日志文件超过 100MB 自动截断保留最后 50MB，
#           防止 Dubbo/ZK 异常导致日志爆炸撑爆磁盘。
# ============================================================
set -euo pipefail

SERVICE="${1:?用法: $0 <eval-boot|eval-answer-boot|perm-boot|basedata-boot|bizgraph-new>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="/tmp/eval-restart-logs"
MAX_LOG_SIZE=$((100 * 1024 * 1024))  # 100MB
TRUNCATE_TO=$((50 * 1024 * 1024))    # 50MB

mkdir -p "$LOG_DIR"

# 服务映射（兼容 macOS bash 3.2，不用关联数组）
JAR_PATH=""
LOG_FILE=""
case "$SERVICE" in
    eval-boot)
        JAR_PATH="$ROOT_DIR/eval_new/eval-boot/target/eval-boot-1.0.0-SNAPSHOT.jar"
        LOG_FILE="$LOG_DIR/eval-boot.log"
        ;;
    eval-answer-boot)
        JAR_PATH="$ROOT_DIR/eval_new/eval-answer-boot/target/eval-answer-boot-1.0.0-SNAPSHOT.jar"
        LOG_FILE="$LOG_DIR/eval-answer-boot.log"
        ;;
    perm-boot)
        JAR_PATH="$ROOT_DIR/perm/perm-boot/target/perm-boot-1.0.0-SNAPSHOT.jar"
        LOG_FILE="$LOG_DIR/perm-boot.log"
        ;;
    basedata-boot)
        JAR_PATH="$ROOT_DIR/base-data-service/base-data-boot/target/base-data-boot-1.0.0-SNAPSHOT.jar"
        LOG_FILE="$LOG_DIR/basedata-boot.log"
        ;;
    bizgraph-new)
        JAR_PATH="$ROOT_DIR/bizgraph_new/target/bizgraph-mcp-0.1.0-SNAPSHOT.jar"
        LOG_FILE="$LOG_DIR/bizgraph-new.log"
        ;;
    *)
        echo "错误: 未知服务 '$SERVICE'"
        echo "可选: eval-boot | eval-answer-boot | perm-boot | basedata-boot | bizgraph-new"
        exit 1
        ;;
esac

if [ ! -f "$JAR_PATH" ]; then
    echo "错误: jar 不存在: $JAR_PATH"
    echo "请先执行 mvn package -DskipTests"
    exit 1
fi

# 日志截断函数: 超过 MAX_LOG_SIZE 则保留最后 TRUNCATE_TO 字节
truncate_log_if_needed() {
    local file="$1"
    if [ -f "$file" ]; then
        local size
        size=$(stat -f%z "$file" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
            echo "[日志保护] $file 大小 $(($size / 1024 / 1024))MB 超过上限，截断保留最后 $(($TRUNCATE_TO / 1024 / 1024))MB"
            local tmp="${file}.truncating"
            tail -c "$TRUNCATE_TO" "$file" > "$tmp" && mv "$tmp" "$file"
        fi
    fi
}

# 后台日志监控: 每 30 秒检查一次日志大小
(
    while true; do
        sleep 30
        truncate_log_if_needed "$LOG_FILE"
    done
) &
MONITOR_PID=$!
trap 'kill $MONITOR_PID 2>/dev/null; exit 0' EXIT INT TERM

echo "[启动] $SERVICE"
echo "  JAR:  $JAR_PATH"
echo "  日志: $LOG_FILE (上限 100MB，自动截断至 50MB)"
echo "  监控进程 PID: $MONITOR_PID"
echo ""

cd "$ROOT_DIR"
# -Duser.home 重定向 Dubbo 缓存到 /tmp（Trae 沙箱不允许写 ~/.dubbo/）
mkdir -p /tmp/dubbo-home/.dubbo
java -Duser.home=/tmp/dubbo-home -jar "$JAR_PATH" --spring.profiles.active=local 2>&1 | tee -a "$LOG_FILE"
