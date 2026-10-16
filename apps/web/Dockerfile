# Hunter Community · Web · Next.js 15 + Node 22
# Multi-stage: deps → build → runtime
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund --registry=https://registry.npmmirror.com

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# NEXT_PUBLIC_* 是构建期烘进客户端产物的，必须在 build 之前作为 ARG 传进来；
# 只在 compose 的 environment 里传是无效的（那是运行时，浏览器拿不到）。
# 默认留空 = 同源相对路径，保持反代部署（演示站）的现有行为不变。
ARG NEXT_PUBLIC_API_URL=""
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# Alpine apk 源走 HTTPS（http 出口被中间设备拦截时 build 会失败）
RUN for f in $(grep -rl 'http://dl-cdn.alpinelinux.org' /etc/apk 2>/dev/null); do sed -i 's#http://dl-cdn.alpinelinux.org#https://dl-cdn.alpinelinux.org#g' "$f"; done
RUN apk add --no-cache curl && \
    addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
# 入口脚本 · 从 hunter_secrets 卷读共享密钥(见脚本头注释)
COPY --chown=nextjs:nodejs entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

USER nextjs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS http://127.0.0.1:3000 || exit 1

CMD ["/app/entrypoint.sh"]
