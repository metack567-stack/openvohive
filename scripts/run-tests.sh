#!/usr/bin/env bash
# 跑全部 Go 测试 + 双向断言（测试文件 ↔ CI 覆盖 / 行为改动 ↔ 测试）
set -euo pipefail
cd "$(dirname "$0")/.."
GO="${GO:-go}"
command -v "$GO" >/dev/null 2>&1 || { echo "❌ 找不到 $GO（CI 里由 setup-go 提供）"; exit 1; }

echo "── go test ./... ──"
"$GO" test ./...
echo "   ✅ 全部 Go 测试通过"

echo
echo "── 双向断言 A：行为改动必须带测试 ──"
if grep -rqF 'autoCopy' internal/ --include='*.go'; then
  grep -rqF 'autoCopy' --include='*_test.go' . \
    || { echo "❌ internal/ 已出现 autoCopy，但仓库里没有对应测试（行为改了没改测试）"; exit 1; }
  echo "   ✅ autoCopy 有测试覆盖"
else
  echo "   ℹ 源码尚未含 autoCopy（立项态允许）"
fi

echo
echo "── 双向断言 B：每个测试文件都要在 CI 覆盖映射里 ──"
map="scripts/ci-test-map.txt"
[ -f "$map" ] || { echo "❌ 缺少 $map"; exit 1; }
rc=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  line="$(grep -F "$f" "$map" || true)"
  if [ -z "$line" ]; then
    echo "❌ 测试文件未纳入 CI 映射: $f"; rc=1
  elif printf '%s' "$line" | grep -q 'SKIPPED:'; then
    echo "   ⚠ 显式跳过（已登记理由）: $line"
  else
    echo "   ✅ 已覆盖: $line"
  fi
done < <(git ls-files '*_test.go' '*test.ts' '*spec.ts' | sort)
[ "$rc" -eq 0 ] || exit 1
echo "   ✅ 双向断言 B 通过"
