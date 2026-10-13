#!/usr/bin/env bash
# 部署脚本：前置检查 → 拉镜像 → force-recreate（断言容器 ID 变了）→ 等就绪 → 核对版本 → 源码遮蔽检查 → 打印
set -euo pipefail
DEPLOY_DIR="${DEPLOY_DIR:-/vol1/1000/Docker/openvohive}"
CT="${CT:-vohive}"
D="sg docker -c"

cd "$DEPLOY_DIR"
[ -f .env ] || { echo "❌ 缺少 $DEPLOY_DIR/.env（IMAGE_TAG / PROXY_WEB_*）"; exit 1; }
set -a; . ./.env; set +a
: "${IMAGE_TAG:?IMAGE_TAG 未设置}"
IMG="ghcr.io/metack567-stack/openvohive:${IMAGE_TAG}"
WANT_VER="${IMAGE_TAG#v}"

echo "① 前置检查：串口互斥（freepbx 与 vohive 都独占 /dev/ttyUSB2）"
if sg docker -c "docker ps --format '{{.Names}}'" | grep -qx freepbx; then
  echo "❌ freepbx 正在运行，会抢 /dev/ttyUSB2：先 sg docker -c 'docker compose -f /vol1/1000/Docker/freepbx/docker-compose.yml stop'"; exit 1
fi
echo "   ✅ 无冲突进程"

echo "② 拉镜像 $IMG"
sg docker -c "docker pull $IMG"

OLD_ID="$(sg docker -c "docker inspect -f '{{.Id}}' $CT" 2>/dev/null || echo none)"
echo "③ 重建（--force-recreate）"
sg docker -c "docker compose up -d --force-recreate"
NEW_ID="$(sg docker -c "docker inspect -f '{{.Id}}' $CT")"
[ "$OLD_ID" != "$NEW_ID" ] || { echo "❌ 容器 ID 未变化，重建没生效"; exit 1; }
echo "   ${OLD_ID:0:12} → ${NEW_ID:0:12} ✅"

echo "④ 等就绪（最多 90s，登录成功为准）"
TOK=""; USER="${PROXY_WEB_USERNAME:-admin}"; PASS="${PROXY_WEB_PASSWORD:?}"
for _ in $(seq 1 45); do
  TOK="$(curl -s -m 3 -X POST http://127.0.0.1:7575/api/auth/login -H 'Content-Type: application/json' \
        -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))' 2>/dev/null || true)"
  [ -n "$TOK" ] && break; sleep 2
done
[ -n "$TOK" ] || { echo "❌ 未就绪"; sg docker -c "docker logs --tail 30 $CT"; exit 1; }
echo "   ✅ 可登录"

echo "⑤ 核对运行版本（必须是 $WANT_VER）"
GOT="$(curl -s -m 5 -H "Authorization: Bearer $TOK" http://127.0.0.1:7575/api/system/info \
      | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("version") or d.get("data",{}).get("version",""))')"
echo "   容器内版本: $GOT"
[ "$GOT" = "$WANT_VER" ] || { echo "❌ 版本不符（镜像没换成功？）"; exit 1; }

echo "⑥ 源码遮蔽检查（不许挂源码进容器）"
if sg docker -c "docker inspect $CT --format '{{range .Mounts}}{{.Source}} {{end}}'" | grep -q 'projects/openvohive'; then
  echo "❌ 检测到容器挂载了源码目录（会遮蔽镜像内代码）"; exit 1
fi
echo "   ✅ 未挂源码"

echo "⑦ 状态"
sg docker -c "docker ps --filter name=$CT --format '{{.Names}}  {{.Status}}  {{.Image}}'"
echo "✅ 部署完成：$IMG"
