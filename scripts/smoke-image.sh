#!/usr/bin/env bash
# 黑盒冒烟：起镜像 → 等可登录 → 核对镜像内版本串 → 清理
# 用法: smoke-image.sh <image> <expected_version>
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${1:-openvohive-nas:ci}"
WANT="${2:-$(cat VERSION)}"
NAME="ov-smoke-$$"
TMP="$(mktemp -d)"
USER=smoke; PASS="smoke-$$"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

# 固定凭据的临时配置（不依赖 env 绑定行为，测的才是镜像本身）
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

TOK=""
for _ in $(seq 1 45); do
  TOK="$(curl -s -m 3 -X POST "http://127.0.0.1:$PORT/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))' 2>/dev/null || true)"
  [ -n "$TOK" ] && break
  sleep 2
done
[ -n "$TOK" ] || { echo "❌ 冒烟失败：容器起不来或登录失败"; docker logs "$NAME" 2>&1 | tail -20; exit 1; }

H="$(curl -s -m 5 -H "Authorization: Bearer $TOK" "http://127.0.0.1:$PORT/api/health")"
echo "   /api/health: $H"

GOT="$(curl -s -m 5 -H "Authorization: Bearer $TOK" "http://127.0.0.1:$PORT/api/system/info" \
      | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("version") or d.get("data",{}).get("version",""))')"
echo "   镜像内版本: '$GOT'  期望: '$WANT'"
[ "$GOT" = "$WANT" ] || { echo "❌ 冒烟失败：版本串不符（镜像没带上 VERSION）"; exit 1; }
echo "✅ 冒烟通过：可登录 + 版本串一致"
