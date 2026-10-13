#!/usr/bin/env bash
# 黑盒冒烟：起镜像 → 等就绪 → 核对镜像内版本串 → 清理
# 用法: smoke-image.sh <image> <expected_version>
#
# 注意（实测坑）：配置优先级是 **环境变量 > config.yaml**
#   —— viper 的 AutomaticEnv 会覆盖配置文件的值（web.username/password 就是如此）。
#   所以这里用 -e PROXY_WEB_* 传凭据，而不挂 config.yaml；
#   另外不挂载就没有 root 写的日志要清（避免 Permission denied 噪声）。
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${1:-openvohive-nas:ci}"
WANT="${2:-$(cat VERSION)}"
NAME="ov-smoke-$$"
USER=smoke; PASS="smoke-$$"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# 端口：交给 docker 随机分配宿主端口（`-p 容器端口` 形式）。
# 不要用 `-p 127.0.0.1::7575`：在 GitHub runner 上实测会得到
# "No public port '7575/tcp' published"。
docker run -d --name "$NAME" -p 7575 \
  -e PROXY_WEB_USERNAME="$USER" -e PROXY_WEB_PASSWORD="$PASS" \
  "$IMG" >/dev/null
PORT=""
for _ in $(seq 1 15); do
  PORT="$(docker port "$NAME" 7575/tcp 2>/dev/null | head -1 | awk -F: '{print $NF}')"
  [ -n "$PORT" ] && break
  sleep 1
done
[ -n "$PORT" ] || { echo "❌ 冒烟失败：端口未发布（容器状态 $(docker inspect -f '{{.State.Status}}' "$NAME")）"; docker logs "$NAME" 2>&1 | tail -15; exit 1; }
echo "   容器 $NAME 端口 $PORT，等待就绪 …"

TOK="$(bash scripts/wait-ready.sh "$PORT" "$USER" "$PASS")" || {
  echo "❌ 冒烟失败：容器起不来或登录失败"; docker logs "$NAME" 2>&1 | tail -20; exit 1; }

H="$(curl -s -m 5 -H "Authorization: Bearer $TOK" "http://127.0.0.1:$PORT/api/health")"
echo "   /api/health: $H"

GOT="$(curl -s -m 5 -H "Authorization: Bearer $TOK" "http://127.0.0.1:$PORT/api/system/info" \
      | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("version") or d.get("data",{}).get("version",""))')"
echo "   镜像内版本: '$GOT'  期望: '$WANT'"
[ "$GOT" = "$WANT" ] || { echo "❌ 冒烟失败：版本串不符（镜像没带上 VERSION）"; docker logs "$NAME" 2>&1 | tail -10; exit 1; }
echo "✅ 冒烟通过：可登录 + 版本串一致"
