#!/bin/sh
# NAS 自建版入口脚本：行为与官方镜像（dannyge/vohive-docker）对齐
#  - 未传 PROXY_WEB_PASSWORD 时随机生成（避免弱默认密码进生产）
#  - 配置持久化到 /app/data/config.yaml（容器重启不丢设备/通知设置）
#  - 日志符号链接到持久化目录
set -eu

if [ -z "${PROXY_WEB_PASSWORD:-}" ]; then
  PROXY_WEB_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)
  printf '\n======== openvohive 未配置密码 ========\n'
  printf '  用户名: %s\n' "${PROXY_WEB_USERNAME:-admin}"
  printf '  密码:   %s\n' "$PROXY_WEB_PASSWORD"
  printf '  (docker logs 可再次查看；重启会换新密码)\n'
  printf '=======================================\n\n'
  export PROXY_WEB_PASSWORD
fi

PERSIST_CONFIG="/app/data/config.yaml"
if [ -n "${VOHIVE_CONFIG:-}" ]; then
  CONFIG="$VOHIVE_CONFIG"
elif [ -f "$PERSIST_CONFIG" ]; then
  CONFIG="$PERSIST_CONFIG"
else
  cp /app/config/config.yaml "$PERSIST_CONFIG"
  CONFIG="$PERSIST_CONFIG"
fi

mkdir -p /app/data/logs
if [ ! -e /app/logs ]; then
  ln -s /app/data/logs /app/logs
fi

exec /app/server -c "$CONFIG" ${VOHIVE_ARGS:-}
