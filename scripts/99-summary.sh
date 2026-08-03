#!/usr/bin/env bash
# 99-summary —— 汇总本次运行的报告账本 + 打印必须手动做的事
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/common.sh"
report_init

if [[ ! -s "$UW_REPORT" ]]; then
  warn "没有报告账本（$UW_REPORT）"
  exit 0
fi

RECENT="$(mktemp)"
trap 'rm -f "$RECENT"' EXIT
awk -F'\t' '$1 !~ /^#/' "$UW_REPORT" | tail -300 > "$RECENT"

n_ok=$(awk -F'\t'   '$4=="ok"'   "$RECENT" | wc -l)
n_skip=$(awk -F'\t' '$4=="skip"' "$RECENT" | wc -l)
n_fail=$(awk -F'\t' '$4=="fail"' "$RECENT" | wc -l)

echo
printf '  %s%d 成功%s · %s%d 跳过%s · %s%d 失败%s\n' \
  "$C_GRN" "$n_ok" "$C_RESET" "$C_DIM" "$n_skip" "$C_RESET" \
  "$([[ $n_fail -gt 0 ]] && printf '%s' "$C_RED" || printf '%s' "$C_DIM")" "$n_fail" "$C_RESET"

if [[ "$n_fail" -gt 0 ]]; then
  echo
  err "失败项："
  awk -F'\t' '$4=="fail" {printf "    [%s] %-24s %s\n", $2, $3, $5}' "$RECENT"
  echo
  info "多数下载失败是上游改了 release asset 名。诊断方法："
  info "  1. ./bootstrap.sh --dry-run   （对每个 URL 发 HEAD，直接指出哪个 404）"
  info "  2. 去上游 releases 页面看新的 asset 名"
  info "  3. 改 manifest/tools.json 的 version / asset 字段"
  info "  4. ./scripts/20-binaries.sh --only <id>"
fi

section "必须手动做的事"
cat <<'EOF'
  1. Termius —— 打开应用，登录你的 Termius 账号。主机、密钥、代码片段
     会从云端同步下来。本仓库只负责把应用装上：它的配置是加密的
     IndexedDB（~/.config/Termius/），不可移植，也不该进版本库。

  2. git 身份 —— 编辑 ~/.gitconfig.local 填 user.name / user.email。
     刻意不放进仓库：仓库是 public 的。

  3. 登录 shell —— 如果 40-zsh 改过，必须【完整注销重新登录】才生效。
     开一个新的终端标签页是没用的。

  4. 字体 —— 已经开着的终端要重启才认新字体。

  5. 中文输入法（fcitx5）—— 本仓库不管。需要的话自己
     apt install fcitx5 fcitx5-chinese-addons，装完注销重登。

完整清单见 docs/manual-steps.md
EOF

section "验证"
echo "  ./verify.sh          检查每一项是否真的到位"
echo "  zsh -l               开一个 zsh 看看效果"
echo
echo "  报告账本：$UW_REPORT"
exit 0
