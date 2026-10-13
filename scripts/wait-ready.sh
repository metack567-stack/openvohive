#!/usr/bin/env bash
# 等服务就绪并登录，把 token 打到 stdout
#
# 为什么单独成文件：登录接口有硬限流 —— 10 次 / 2 分钟 / IP
# （见 internal/api/server.go 的 allowLoginAttempt，window=2min, limit=10）。
# smoke-image.sh 与 deploy.sh 都必须遵守；复制两份必然漂移（规范 §4.4）。
#
# 用法: wait-ready.sh <port> <username> <password>
set -euo pipefail
PORT="${1:?用法: wait-ready.sh <port> <username> <password>}"
USER="${2:?缺少用户名}"
PASS="${3:?缺少密码}"
BASE="http://127.0.0.1:$PORT"

# ① 就绪判定走免鉴权的前端首页（/api/* 全部在鉴权后面，不能用来判就绪）
code=""
for _ in $(seq 1 45); do
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 3 "$BASE/" || true)"
  [ "$code" = "200" ] && break
  sleep 2
done
[ "$code" = "200" ] || { echo "❌ 服务未就绪：GET / 返回 $code（等待约 90s）" >&2; exit 1; }

# ② 登录：最多 3 次、间隔 20s —— 远低于 10 次/2min 的限流阈值
for i in 1 2 3; do
  TOK="$(curl -s -m 5 -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
        -d "{\"username\":\"$USER\",\"password\":\"$PASS\"}" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))' 2>/dev/null || true)"
  if [ -n "$TOK" ]; then printf '%s' "$TOK"; exit 0; fi
  echo "   ⚠ 第 $i 次登录未成功（若为 429 = 触发限流），20s 后重试" >&2
  sleep 20
done
echo "❌ 登录连续 3 次失败" >&2
exit 1
