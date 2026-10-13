# syntax=docker/dockerfile:1.4
# NAS 自建版：与上游 Dockerfile（需预构建 ./app）不同，这里**自包含**构建
# 前端(Bun) → 后端(Go) → 运行时(Alpine)。不依赖挂载源码，CI 与线上同一份构建。
# 注入版本号：--build-arg VOHIVE_VERSION=$(cat VERSION)

# ── Stage 1: 前端 ────────────────────────────────────────
FROM oven/bun:1-alpine AS frontend
WORKDIR /build
COPY web/package.json web/bun.lock* ./web/
RUN cd web && (bun install --frozen-lockfile || bun install)
COPY web/ ./web/
RUN cd web && bun run build

# ── Stage 2: 后端 ────────────────────────────────────────
FROM golang:1.26-alpine AS backend
RUN apk add --no-cache git
WORKDIR /build
COPY . .
COPY --from=frontend /build/web/dist ./web/dist
ARG VOHIVE_VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w \
      -X github.com/openvohive/openvohive/internal/global.Version=${VOHIVE_VERSION} \
      -X github.com/openvohive/openvohive/internal/global.BuildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -trimpath -o /out/server .

# ── Stage 3: 运行时 ──────────────────────────────────────
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata libc6-compat && \
    (cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true)
WORKDIR /app
COPY --from=backend /out/server /app/server
COPY config/config.example.yaml /app/config/config.yaml
COPY deploy/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/server /app/docker-entrypoint.sh
RUN mkdir -p /app/data
# 数据/配置/日志约定（与官方镜像一致）：挂 ./data → /app/data
ENTRYPOINT ["/app/docker-entrypoint.sh"]
