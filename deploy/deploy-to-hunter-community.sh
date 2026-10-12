#!/usr/bin/env bash
#
# deploy/deploy-to-hunter-community.sh
#
# ┌─ 目标设备 (TARGET DEVICE) ───────────────────────────────────────────┐
# │ 主机     : 10.98.136.105  (用户 xuyan —— 远程服务器, 非本机)          │
# │ 目标目录 : /Users/xuyan/Desktop/hunter-community  (在上面的服务器上)   │
# │ 作用     : 把此 Mac 上的源码同步到该远程设备并 docker compose up -d   │
# └──────────────────────────────────────────────────────────────────────┘
#
# 前置: 本机已安装 sshpass、rsync。
# 用法:
#   ./deploy/deploy-to-hunter-community.sh            # 同步文件并 docker compose up -d
#   ./deploy/deploy-to-hunter-community.sh pull       # 仅拉取镜像
#   ./deploy/deploy-to-hunter-community.sh restart    # 重新同步并重启
#   ./deploy/deploy-to-hunter-community.sh down       # 停止
#   ./deploy/deploy-to-hunter-community.sh logs       # 看日志(-f 自行加)
#   ./deploy/deploy-to-hunter-community.sh status     # 看容器状态
#
# 服务器密码优先级: 环境变量 HUNTER_DEPLOY_PASS > deploy/.pass(自建,已 gitignore) > 交互输入
#   export HUNTER_DEPLOY_PASS='你的密码' && ./deploy/deploy-remote.sh
#
# 可用环境变量覆盖默认值:
#   DEPLOY_HOST / DEPLOY_USER / DEPLOY_DIR / COMPOSE_FILE

set -euo pipefail

REMOTE_HOST="${DEPLOY_HOST:-10.98.136.105}"
REMOTE_USER="${DEPLOY_USER:-xuyan}"
REMOTE_DIR="${DEPLOY_DIR:-/Users/xuyan/Desktop/hunter-community}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"

CMD="${1:-up}"
case "$CMD" in
  up)     COMPOSE_ARGS="up -d" ;;
  status) COMPOSE_ARGS="ps" ;;
  *)      COMPOSE_ARGS="$CMD" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── 取服务器密码 ─────────────────────────────────────────
if [ -n "${HUNTER_DEPLOY_PASS:-}" ]; then
  PASS="$HUNTER_DEPLOY_PASS"
elif [ -f "$SCRIPT_DIR/.pass" ]; then
  PASS="$(cat "$SCRIPT_DIR/.pass")"
else
  read -r -s -p "远程服务器密码: " PASS; echo
fi
export SSHPASS="$PASS"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
REMOTE="${REMOTE_USER}@${REMOTE_HOST}"

# ── 需要重新同步文件的操作 ──────────────────────────────
if [ "$CMD" = "up" ] || [ "$CMD" = "restart" ]; then
  echo "▶ 同步部署文件 -> ${REMOTE}:${REMOTE_DIR}"
  sshpass -e rsync -az \
    -e "ssh ${SSH_OPTS[*]}" \
    --exclude '.git' \
    "$LOCAL_DIR/docker-compose.yml" \
    "$LOCAL_DIR/.env" \
    "$LOCAL_DIR/deploy" \
    "${REMOTE}:${REMOTE_DIR}/"
fi

# 服务器上 docker 不在默认 PATH,且需指定 DOCKER_HOST(可按环境覆盖)
REMOTE_DOCKER_PATH="${REMOTE_DOCKER_PATH:-/usr/local/bin}"
REMOTE_DOCKER_HOST="${REMOTE_DOCKER_HOST:-unix:///Users/xuyan/.docker/run/docker.sock}"

echo "▶ 在服务器执行: docker compose -f $COMPOSE_FILE $COMPOSE_ARGS"
sshpass -e ssh "${SSH_OPTS[@]}" "${REMOTE}" \
  "export PATH='${REMOTE_DOCKER_PATH}':\$PATH DOCKER_HOST='${REMOTE_DOCKER_HOST}'; cd '${REMOTE_DIR}' && docker compose -f '${COMPOSE_FILE}' ${COMPOSE_ARGS}"
