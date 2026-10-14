# Hunter Community · Paper Service · 唯一账本 + 确定性风控
#
# 与 apps/api 同栈（FastAPI + psycopg2-binary），但**独立镜像、独立进程**：
# 它是全仓唯一持有 `fin_paper_rw` 连接的服务（08 §二「服务落点」）。
#
# 构建上下文是 `apps/paper/`（自包含，不依赖仓库里 skills/ / data/ / db/migrations）。
# 默认 compose 文件里不写 build，只用预构建镜像；开发用 docker-compose.dev.yml 才加 build。
#
# 构建： docker build -f apps/paper/Dockerfile -t hunter-community-paper apps/paper
#
# ⚠️ 本镜像**完全不依赖 apt 源**：psycopg2-binary 是预编译 wheel（自带 libpq，
#    构建期不需要 build-essential / libpq-dev）；运行时 tzdata 改由 pip 安装
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
# ⚠️ `boot.sh` 必须一起 COPY 进来：`CMD` 指向 `/app/boot.sh`，不拷就是
#    「镜像构建成功、一跑就 exec: /app/boot.sh: no such file or directory」。
COPY boot.sh /app/boot.sh
RUN chmod +x /app/boot.sh

EXPOSE 8000

# /healthz 是唯一免密钥端点。用 python 内置 urllib 探活，避免依赖 apt 装的 curl。
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request,sys; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3); sys.exit(0)" || exit 1

# 入口换成 boot.sh：自检（模式 / 口令 / 库权限）→ 起 uvicorn。
# 自检不过就起不来 —— 缺表 / 连不上的实例「看着健康、一点就 500」比直接起不来难排查。
CMD ["/app/boot.sh"]
