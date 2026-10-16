# Hunter Community · API · Python 3.11 slim · 多阶段
#
# 为什么多阶段:单阶段版本把 build-essential(gcc/g++/头文件,约 400 MB)和
# libpq-dev 留在了运行层,而它们只在 pip 装包时可能用到 —— 镜像 1.32 GB 里
# 有三成是运行时一次也不会执行的编译器。
#
# 现在:builder 装进 venv,运行层只拷 venv。运行层保留 tesseract(OCR 要的是
# 二进制本身,不是编译器)与 curl(HEALTHCHECK)。
# P1 skeleton · minimal boot supported via HUNTER_MINIMAL_BOOT=1
#
# ⚠️ 构建上下文是**仓库根**,不是 apps/api:
#     docker build -f apps/api/Dockerfile -t hunter-community-api .
# 因为镜像要自带 skills/ 、data/ 、db/migrations/ —— 它们在 apps/api 外面,
# 而 Dockerfile 不允许 COPY 上下文之外的路径。
# 生效的忽略文件因此是**仓库根的 .dockerignore**(apps/api/.dockerignore 不再生效)。

# ─── builder ────────────────────────────────────────────────
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# 有些包没有对应平台的 wheel 时要就地编译(arm64 上尤其常见),所以 builder 里
# 该给的编译工具还是得给 —— 只是不再让它们进运行层。
# 构建环境 apt 源走 HTTPS（http 出口被中间设备拦截时 build 会失败）
RUN for f in $(grep -rl 'http://deb.debian.org' /etc/apt 2>/dev/null); do sed -i 's#http://deb.debian.org#https://deb.debian.org#g' "$f"; done
RUN find /etc/apt -type f \( -name 'sources.list' -o -name '*.sources' \) -exec sed -i 's#deb.debian.org/debian#mirrors.tuna.tsinghua.edu.cn/debian#g' {} +
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# 装进独立 venv 而不是 --target:uvicorn / alembic 这类 console_scripts 要留在
# bin/ 下才能直接当命令用,--target 装法会把它们丢在一个不在 PATH 上的目录里。
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

ARG PIP_INDEX_URL
ENV PIP_INDEX_URL=$PIP_INDEX_URL
COPY apps/api/requirements.txt ./
RUN pip install -r requirements.txt

# ─── runtime ────────────────────────────────────────────────
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/opt/venv/bin:$PATH"

# curl · HEALTHCHECK
# tesseract-ocr · OCR 底层 · chi-sim=中文简体 · eng=英文(混排常见) · 用户上传截图批量加自选走这条链
# 注意:psycopg2-binary 自带 libpq,所以运行层不需要 libpq-dev / libpq5。
# 构建环境 apt 源走 HTTPS（http 出口被中间设备拦截时 build 会失败）
RUN for f in $(grep -rl 'http://deb.debian.org' /etc/apt 2>/dev/null); do sed -i 's#http://deb.debian.org#https://deb.debian.org#g' "$f"; done
RUN find /etc/apt -type f \( -name 'sources.list' -o -name '*.sources' \) -exec sed -i 's#deb.debian.org/debian#mirrors.tuna.tsinghua.edu.cn/debian#g' {} +
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        tesseract-ocr \
        tesseract-ocr-chi-sim \
        tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

# 排除项见**仓库根**的 .dockerignore(apps/api/tests 、__pycache__ 、*.pyc 等不进镜像)
COPY apps/api /app

# ── 原来靠 bind mount 送进容器的三份数据,现在打进镜像 ──────────
# 打进镜像而不是挂载,是为了让「没有仓库目录」的云平台也能跑起来。
# 代价是换推荐位 / 换内置 SKILL 要重建镜像 —— 本地开发仍可用
# docker-compose.dev.yml 把这三处挂回去,改完立即生效。
#
# 内置 SKILL(原 ./skills:/opt/hunter-skills:ro)· api **永远不该改它们**,
# 「恢复默认永远改不坏」这条靠的就是内置层只读。用户 SKILL 走具名卷
# hunter_user_skills:/opt/hunter-user-skills。
COPY skills /opt/hunter-skills
# 随代码分发的静态数据(原 ./data:/opt/hunter-data:ro)· 推荐 SKILL 清单、股票名称基线表等
COPY data /opt/hunter-data
# 迁移 SQL(原来挂给 postgres 当 initdb,只在数据卷第一次初始化时执行 ——
# 已有部署永远跑不到)。现在改由 api 启动时执行(boot.sh → app.migrate,子任务 B)。
# ⚠️ 路径 /opt/hunter-migrations 是迁移执行器写死读的位置,**不要改名**。
COPY db/migrations /opt/hunter-migrations
# tool schema 清洗函数(M2 · 设计方案 4.5)· **与 llm-shim 共用同一个文件**。
# 向导第 3 步的"工具调用"检测由 api 发出,清洗规则必须和 shim 一模一样,
# 否则会出现"向导说能用、实际对话一发就 400"(或者反过来)。
# 在 api 里另存一份副本迟早会漂,所以这里拷的是 shim 的那一份原文件。
# 读取方:app/services/llm_probe.py::_load_schema_clean()
COPY scripts/llm-shim/schema_clean.py /opt/hunter-shim/schema_clean.py

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/api/health || exit 1

# 入口换成 boot.sh:密钥就位 → 数据库迁移 → 起 uvicorn(见 apps/api/boot.sh)。
# 直接 CMD uvicorn 的话,迁移永远不会跑,表现是「服务看着健康、一点就 500」。
CMD ["/app/boot.sh"]
