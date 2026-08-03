#!/usr/bin/env bash
# 40-zsh —— clone 5 个插件到钉死的 commit，然后（可选）把 zsh 设为登录 shell
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/common.sh"
uw_detect_arch
report_init
need_jq

RC=0

command -v git >/dev/null 2>&1 || { err "缺 git，装不了插件"; report 40 plugins fail "缺 git"; exit 3; }

DEST="$(uw_tmpl "$(jq -r '.dest' "$UW_PLUGINS_JSON")")"
[[ "$DRY_RUN" == 1 ]] || mkdir -p "$DEST" "$COMPLETION_DIR" "$HOME/.cache/zsh"

# ── 插件 ────────────────────────────────────────────────────────
mapfile -t PLUGIN_IDS < <(jq -r '.plugins[].id' "$UW_PLUGINS_JSON")

for id in "${PLUGIN_IDS[@]}"; do
  repo="$(jq -r --arg i "$id" '.plugins[]|select(.id==$i)|.repo' "$UW_PLUGINS_JSON")"
  sha="$(jq -r  --arg i "$id" '.plugins[]|select(.id==$i)|.sha'  "$UW_PLUGINS_JSON")"
  dir="$DEST/$id"

  if [[ -d "$dir/.git" ]]; then
    cur="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$cur" == "$sha" && "$FORCE" != 1 ]]; then
      skip "$id 已在 ${sha:0:8}"
      report 40 "plugin:$id" skip "${sha:0:8}"
      continue
    fi
    if [[ "$DRY_RUN" == 1 ]]; then
      printf '%s  DRY  %s：${cur:0:8} → %s%s\n' "$C_DIM" "$id" "${sha:0:8}" "$C_RESET"
      continue
    fi
    # 已有 clone：fetch 后 checkout，绝不 merge（避免本地改动引发冲突）
    if git -C "$dir" fetch --quiet origin "$sha" 2>/dev/null || git -C "$dir" fetch --quiet origin 2>/dev/null; then
      if git -C "$dir" checkout --quiet --detach "$sha" 2>/dev/null; then
        ok "$id → ${sha:0:8}"
        report 40 "plugin:$id" ok "${sha:0:8}"
      else
        err "$id：checkout $sha 失败"
        report 40 "plugin:$id" fail "checkout 失败"
        RC=3
      fi
    else
      warn "$id：fetch 失败，保留现状 ${cur:0:8}"
      report 40 "plugin:$id" fail "fetch 失败"
      [[ "$RC" == 0 ]] && RC=2
    fi
    continue
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  clone %s → %s @ %s%s\n' "$C_DIM" "$repo" "$dir" "${sha:0:8}" "$C_RESET"
    continue
  fi

  [[ -e "$dir" ]] && { warn "$dir 存在但不是 git 仓库，挪走"; mv "$dir" "$dir.bak.$(date +%s)"; }

  if git clone --quiet "$repo" "$dir" 2>/dev/null \
     && git -C "$dir" checkout --quiet --detach "$sha" 2>/dev/null; then
    ok "$id → ${sha:0:8}"
    report 40 "plugin:$id" ok "${sha:0:8}"
  else
    err "$id：clone/checkout 失败（$repo）"
    report 40 "plugin:$id" fail "$repo"
    RC=3
  fi
done

# ── 登录 shell ──────────────────────────────────────────────────
# 刻意放最后，且必须问过人。
ZSH_BIN="$(uw_which zsh)"
if [[ -z "$ZSH_BIN" ]]; then
  warn "zsh 不在 PATH 上，跳过 chsh（先让 10-apt 装上 zsh）"
  report 40 chsh fail "zsh 缺失"
  [[ "$RC" == 0 ]] && RC=2
  exit "$RC"
fi

CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" == *zsh ]]; then
  skip "登录 shell 已经是 $CURRENT_SHELL"
  report 40 chsh skip "$CURRENT_SHELL"
  exit "$RC"
fi

if [[ "$DRY_RUN" == 1 ]]; then
  printf '%s  DRY  chsh -s %s %s（当前 %s）%s\n' "$C_DIM" "$ZSH_BIN" "$USER" "$CURRENT_SHELL" "$C_RESET"
  exit "$RC"
fi

if [[ "$NO_SUDO" == 1 ]]; then
  warn "--no-sudo：不改登录 shell。手动执行：chsh -s $ZSH_BIN"
  report 40 chsh skip "--no-sudo"
  exit "$RC"
fi

if ! confirm "把登录 shell 从 $CURRENT_SHELL 换成 $ZSH_BIN？（需要完整注销重登才生效）" y; then
  info "跳过。想换时执行：chsh -s $ZSH_BIN"
  report 40 chsh skip "用户拒绝"
  exit "$RC"
fi

# /etc/shells 里没有的话 chsh 会拒绝
if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
  info "把 $ZSH_BIN 加进 /etc/shells"
  sudo_run tee -a /etc/shells >/dev/null <<< "$ZSH_BIN"
fi

# 优先用 sudo chsh —— 用已经拿到的 sudo 凭据，不再单独问一次用户密码
if sudo_run chsh -s "$ZSH_BIN" "$USER"; then
  ok "登录 shell → $ZSH_BIN"
  warn "必须完整注销重新登录才生效 —— 开新终端标签页是没用的"
  report 40 chsh ok "$ZSH_BIN（需重新登录）"
else
  warn "chsh 失败。手动执行：chsh -s $ZSH_BIN"
  report 40 chsh fail "手动执行 chsh -s $ZSH_BIN"
  [[ "$RC" == 0 ]] && RC=2
fi

exit "$RC"
