#!/usr/bin/env bash
# 凭据泄漏检查：只扫纳入版本控制的文件
# 注意：模式用字符串拼接构造，避免扫描器匹配到自身的字面量（自指陷阱）
set -euo pipefail
cd "$(dirname "$0")/.."

PATS=(
  "gh""p_[A-Za-z0-9]{30,}"
  "github""_pat_[A-Za-z0-9_]{30,}"
  "AKIA""[0-9A-Z]{16}"
  "xox""b-[0-9A-Za-z-]{10,}"
  "-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "bark[_-]?device[_-]?key[\"'\"'= :]+[A-Za-z0-9]{16,}"
  "\"device_key\"[[:space:]]*:[[:space:]]*\"[A-Za-z0-9]{16,}\""
)
fail=0
for p in "${PATS[@]}"; do
  hits="$(git grep -InE "$p" -- . ':(exclude)scripts/check-secrets.sh' || true)"
  hits="$(printf '%s\n' "$hits" | grep -v -e 'REDACTED' -e 'example' -e 'your' || true)"
  if [ -n "${hits//[$'\n']/}" ]; then
    echo "❌ 疑似凭据（模式片段: ${p:0:10}…）"
    printf '%s\n' "$hits" | head -5
    fail=1
  fi
done
if [ "$fail" -eq 0 ]; then echo "✅ 凭据泄漏检查通过"; fi
exit "$fail"
