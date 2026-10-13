#!/usr/bin/env bash
# 黑盒冒烟：起镜像 → 等就绪（走中间件感知的就绪入口）→ 核对镜像内版本串 → 清理
# 用法: smoke-image.sh <image> <expected_version>
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${1:-openvohive-nas:ci}"
WANT="${2:-$(cat VERSION)}"
NAME="ov-smoke-$$"
TMP="$(mktemp -d)"
USER=smoke; PASS="smoke-$$"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # 容器内的进程以 root 写日志，宿主直接 rm 会 Permission denied → 用容器清
  docker run --rm -v "$TMP:/x" alpine:latest sh -c 'rm -rf /x/* /x/.[!.]* 2>/dev/null' >/dev/null 2>&1 || true
  rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

cat > "$TMP/config.yaml" <<EOF
server:
  port: 7575
web:
  username: $USER
  password: $PASS
bark:
  enabled: false
EOF

docker run -d --name "$NAME" -p 127.0.0.1::7575 -v "$TMP:/app/data" "$IMG" >/dev/null
PORT="$(docker port "$NAME" 7575/tcp | head -1 | awk -F: '{print $NF}')"
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
