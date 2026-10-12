#!/usr/bin/env bash
#
# deploy-local-source.sh — 把本机最新源码在服务器本地从源码构建并部署
#
# 设计约束（见对话）：
#   - 本机无 Docker；服务器到 docker.io / PyPI / apt 外网不通，只缓存了 daocloud 镜像。
#   - 因此「不推送任何镜像库」，改为在服务器用 dev-compose 直接 FROM 本地缓存的基础镜像
#     + COPY 本机源码，生成 *:dev 镜像（分层缓存，二次构建不重新下载）。
#   - 时区等配置由 docker-compose.local.yml 注入（TZ=Asia/Shanghai）。
#
# 用法：
#   export SSHPASS='你的密码'          # 或创建 deploy/.deploy-secrets (内容: SSHPASS=你的密码)
#   ./deploy/deploy-local-source.sh            # 全量：同步 + 构建 + 启动
#   ./deploy/deploy-local-source.sh --no-sync  # 跳过 rsync，仅重建（源码已在服务器时）
#
# 可用环境变量覆盖默认值：
#   DEPLOY_HOST / DEPLOY_USER / DEPLOY_PATH / LOCAL_REPO
#
set -euo pipefail

# ─── 配置 ───────────────────────────────────────────────
DEPLOY_HOST="${DEPLOY_HOST:-10.98.136.105}"
DEPLOY_USER="${DEPLOY_USER:-xuyan}"
DEPLOY_PATH="${DEPLOY_PATH:-/Users/xuyan/Desktop/hunter-community}"
LOCAL_REPO="${LOCAL_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
SOURCE_SERVICES=(api web opencode llm-shim)

# SSHPASS：优先环境变量，其次 deploy/.deploy-secrets
if [ -z "${SSHPASS:-}" ] && [ -f "$(dirname "$0")/.deploy-secrets" ]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/.deploy-secrets"
fi
if [ -z "${SSHPASS:-}" ]; then
  echo "错误: 未提供 SSH 密码。请 'export SSHPASS=...' 或创建 deploy/.deploy-secrets (内容: SSHPASS=...)" >&2
  exit 1
fi

# ─── 选项解析 ───────────────────────────────────────────
NO_SYNC=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--no-sync) NO_SYNC=1; shift ;;
    -h|--help) echo "用法: $0 [--no-sync]"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15)
RSYNC_EXCLUDES=(
  --exclude='.git'
  --exclude='docs'
  --exclude='data-packages'
  --exclude='user-skills'
  --exclude='.venv'
  --exclude='node_modules'
  --exclude='__pycache__'
  --exclude='*.pyc'
)
ts() { date '+%H:%M:%S'; }

# ─── 1) 同步源码 ───────────────────────────────────────
echo "$(ts) ==> [1/4] 同步源码到 ${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}"
if [ "$NO_SYNC" -eq 0 ]; then
  sshpass -e rsync -az "${RSYNC_EXCLUDES[@]}" \
    -e "ssh ${SSH_OPTS[*]}" \
    "${LOCAL_REPO}/" "${DEPLOY_USER}@${DEPLOY_HOST}:${DEPLOY_PATH}/"
  echo "$(ts)    源码同步完成"
else
  echo "$(ts)    (跳过同步 --no-sync)"
fi

# ─── 2) 服务器本地从源码构建 ──────────────────────────
echo "$(ts) ==> [2/4] 在服务器本地从源码构建镜像（基础镜像走本地缓存，不重新下载）"
sshpass -e ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" \
  DEPLOY_PATH="$DEPLOY_PATH" bash -s <<'REMOTE'
  export PATH=/usr/local/bin:$PATH
  export DOCKER_HOST=unix:///Users/xuyan/.docker/run/docker.sock
  cd "$DEPLOY_PATH"

  echo "$(date '+%H:%M:%S')   -- 确保基础镜像本地标签存在（缺失则从 daocloud 镜像 tag）--"
  ensure() {
    local canon="$1" mirror="$2"
    if docker image inspect "$canon" >/dev/null 2>&1; then
      echo "     ✔ $canon 已存在"
      return
    fi
    echo "     ⚠ $canon 缺失，尝试从镜像 tag: $mirror"
    if docker image inspect "$mirror" >/dev/null 2>&1; then
      docker tag "$mirror" "$canon"
    else
      echo "     拉取 $canon (经 daemon 镜像加速) ..."
      docker pull "$canon" || { echo "     拉取 $canon 失败（无外网？）"; exit 1; }
    fi
  }
  ensure python:3.11-slim       docker.m.daocloud.io/library/python:3.11-slim
  ensure python:3.12-alpine     docker.m.daocloud.io/library/python:3.12-alpine
  ensure node:22-alpine         docker.m.daocloud.io/library/node:22-alpine
  ensure node:22-slim           docker.m.daocloud.io/library/node:22-slim
  ensure ghcr.io/agentpit-io/hunter-opencode:1.18.12-slim.1 \
         ghcr.nju.edu.cn/agentpit-io/hunter-opencode:1.18.12-slim.1

  echo "$(date '+%H:%M:%S')   -- 构建源码镜像（分层缓存，仅改动层重跑；npm 等若需联网请确认服务器可达）--"
  docker compose -f docker-compose.yml -f docker-compose.dev.yml -f docker-compose.local.yml \
    build "${SOURCE_SERVICES[@]}"
REMOTE

# ─── 3) 启动 / 重建全部服务 ──────────────────────────
echo "$(ts) ==> [3/4] 启动 / 重建全部服务"
sshpass -e ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" \
  DEPLOY_PATH="$DEPLOY_PATH" bash -s <<'REMOTE'
  export PATH=/usr/local/bin:$PATH
  export DOCKER_HOST=unix:///Users/xuyan/.docker/run/docker.sock
  cd "$DEPLOY_PATH"
  docker compose -f docker-compose.yml -f docker-compose.dev.yml -f docker-compose.local.yml up -d
REMOTE

# ─── 4) 健康检查 ───────────────────────────────────────
echo "$(ts) ==> [4/4] 健康检查（等待 api 变为 healthy）"
sshpass -e ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" \
  DEPLOY_PATH="$DEPLOY_PATH" bash -s <<'REMOTE'
  export PATH=/usr/local/bin:$PATH
  export DOCKER_HOST=unix:///Users/xuyan/.docker/run/docker.sock
  cd "$DEPLOY_PATH"
  CID=$(docker compose ps -q api)
  for i in $(seq 1 12); do
    S=$(docker inspect -f '{{.State.Health.Status}}' "$CID" 2>/dev/null || echo unknown)
    echo "     try $i: api=$S"
    [ "$S" = "healthy" ] && break
    sleep 5
  done
  echo "  -- 服务状态 --"
  docker compose ps
  echo "  -- api 日志尾部 --"
  docker logs --tail 8 "$CID" 2>&1 | sed 's/^/     /'
REMOTE

echo "==> 完成。本机源码已通过本地构建部署到服务器（未推送任何镜像库）。"
