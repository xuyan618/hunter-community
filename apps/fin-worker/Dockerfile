# Hunter Community · fin-worker · Runtime Bridge + Temporal Workers
#
# 与 apps/paper 同栈（Python），但**独立镜像、独立进程**：它不连账本库，
# 只经 paper 的 HTTP 改账本（01方案 §7.4 / §11.3）。依赖里没有 psycopg2 ——
# 「不直连账本」是一条能被 grep 出来的事实，不是一句注释。
#
# 构建上下文是 `apps/fin-worker/`（不是仓库根）。
# 构建： docker build -f apps/fin-worker/Dockerfile -t hunter-community-fin-worker apps/fin-worker
#
# ⚠️ 本镜像**完全不依赖 apt 源**：无任何 DB 驱动；运行时 tzdata 改由 pip 安装
#    （zoneinfo 自动使用），健康检查改用 python 内置 urllib。因此在 apt 源被代理
#    破坏的内网也能只靠阿里云 PyPI（PIP_INDEX_URL）正常构建。

# ─── builder ────────────────────────────────────────────────
FROM python:3.11-slim AS builder

ARG PIP_INDEX_URL
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_INDEX_URL=${PIP_INDEX_URL:-}

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt ./
# tzdata 一并装进 venv，运行时 COPY 即得（zoneinfo 自动读取）
RUN pip install -r requirements.txt tzdata

# ─── runtime ────────────────────────────────────────────────
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY app /app/app
COPY boot.sh /app/boot.sh
RUN chmod +x /app/boot.sh

EXPOSE 8300

# /healthz 免密钥。用 python 内置 urllib 探活，避免依赖 apt 装的 curl。
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python3 -c "import urllib.request,sys; urllib.request.urlopen('http://127.0.0.1:8300/healthz', timeout=3); sys.exit(0)" || exit 1

CMD ["/app/boot.sh"]
