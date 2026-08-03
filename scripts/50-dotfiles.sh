#!/usr/bin/env bash
# 50-dotfiles —— 把 home/ 下的配置落地到 $HOME
#
# 默认全部软链（home/X → ~/X，映射可推导，加文件不用改登记表）。
# manifest/dotfiles.tsv 只登记「不走默认行为」的少数条目。
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/link.sh"
uw_detect_arch
report_init

RC=0
TSV="$UW_ROOT/manifest/dotfiles.tsv"

# 读 tsv：repo_path -> mode
declare -A MODE_OF=()
if [[ -f "$TSV" ]]; then
  while IFS=$'\t' read -r rp target mode note; do
    [[ -z "${rp:-}" || "$rp" == \#* ]] && continue
    MODE_OF["$rp"]="$mode"
  done < "$TSV"
fi

# ── 1. 走默认 link 的：home/ 下所有普通文件 ─────────────────────
while IFS= read -r -d '' src; do
  rel="${src#"$UW_ROOT"/}"                 # home/.config/ghostty/config
  mode="${MODE_OF[$rel]:-link}"
  target="$HOME/${rel#home/}"

  case "$mode" in
    skip) debug "跳过（tsv 标 skip）：$rel"; continue ;;
    copy) uw_copy "$src" "$target" ;;
    link) uw_link "$src" "$target" ;;
    generate) : ;;                          # 下面单独处理
    *)    warn "$rel：未知 mode '$mode'，按 link 处理"; uw_link "$src" "$target" ;;
  esac
  rc=$?
  [[ "$rc" -gt 10 ]] && { RC=2; report 50 "$rel" fail "mode=$mode"; }
done < <(find "$UW_ROOT/home" -type f -print0 2>/dev/null)

# ── 2. 示例文件初始化（存在则绝不覆盖）─────────────────────────
uw_seed "$UW_ROOT/home/.zshrc.local.example"      "$HOME/.zshrc.local"
uw_seed "$UW_ROOT/git/gitconfig.local.example"    "$HOME/.gitconfig.local"

# ── 3. ~/.gitconfig：generate，不软链 ──────────────────────────
uw_generate_gitconfig "$UW_ROOT/git/gitconfig"

# 身份提醒。刻意不自动写 —— 绝不猜用户的名字和邮箱。
if [[ "$DRY_RUN" != 1 ]]; then
  gname="$(git config --file "$HOME/.gitconfig.local" user.name 2>/dev/null || true)"
  gmail="$(git config --file "$HOME/.gitconfig.local" user.email 2>/dev/null || true)"
  if [[ -z "$gname" || "$gname" == "YOUR NAME" || "$gmail" == "you@example.com" ]]; then
    warn "git 身份还没填。编辑 ~/.gitconfig.local，或："
    warn "    git config --global user.name  \"你的名字\""
    warn "    git config --global user.email \"you@example.com\""
    report 50 git-identity na "待用户填写"
  else
    ok "git 身份已配置（$gname）"
    report 50 git-identity ok "已配置"
  fi
fi

# ── 4. ~/.profile 围栏块：给非 zsh 的登录会话也补上 PATH ────────
uw_append_block "$HOME/.profile" "$(cat <<'EOF'
# ~/.local/bin 与 node20 加进 PATH。zsh 用户由 ~/.zshrc 处理（还带
# typeset -U 去重），这里是给 sh/bash 登录会话和图形会话用的。
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
  *":$HOME/.local/opt/node20/bin:"*) ;;
  *) PATH="$HOME/.local/opt/node20/bin:$PATH" ;;
esac
export PATH
EOF
)"

# ── 5. tmux 配置自检（GAP-FIX #3）──────────────────────────────
if [[ "$DRY_RUN" != 1 ]] && command -v tmux >/dev/null 2>&1; then
  if tmux -f "$HOME/.tmux.conf" start-server \; kill-server >/dev/null 2>&1; then
    ok "~/.tmux.conf 语法 OK"
    report 50 tmux-conf ok ""
  else
    warn "~/.tmux.conf 有 tmux 不认的指令（版本差异？tmux $(tmux -V)）"
    report 50 tmux-conf fail "语法检查未通过"
    [[ "$RC" == 0 ]] && RC=2
  fi
fi

[[ "$RC" == 0 ]] && report 50 dotfiles ok "已落地"
exit "$RC"
