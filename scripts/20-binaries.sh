#!/usr/bin/env bash
# 20-binaries —— manifest 里所有 github_release 工具 → ~/.local/bin
# 本仓库的主力步骤。零提权。
#
# 单独重跑某一个：./scripts/20-binaries.sh --only eza
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/fetch.sh"
uw_detect_arch
report_init
need_jq

ONLY_IDS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY_IDS="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) shift ;;
  esac
done

RC=0
mkdir -p "$BIN_DIR" "$COMPLETION_DIR" "$MAN_DIR"

mapfile -t IDS < <(tools_in_profile github_release)

for id in "${IDS[@]}"; do
  [[ -n "$ONLY_IDS" && ",$ONLY_IDS," != *",$id,"* ]] && continue

  version="$(tool_field "$id" '.version')"
  required="$(tool_field "$id" '.required')"
  repo="$(tool_field "$id" '.github.repo')"
  tag="$(tool_field "$id" '.github.tag')"
  asset="$(tool_field "$id" '.github.asset')"
  pick="$(tool_field "$id" '.github.pick')"
  strip="$(tool_field "$id" '.github.strip')"
  as="$(tool_field "$id" '.github.as')"
  vcmd="$(tool_field "$id" '.verify.cmd')"
  vre="$(tool_field "$id" '.verify.regex')"
  post="$(tool_field "$id" '.post_install')"

  args=(--name "$id" --version "$version" --repo "$repo" --tag "$tag" --asset "$asset")
  [[ -n "$pick"  ]] && args+=(--pick "$pick")
  [[ -n "$strip" ]] && args+=(--strip "$strip")
  [[ -n "$as"    ]] && args+=(--as "$as")
  [[ -n "$vcmd"  ]] && args+=(--check "$vcmd")
  [[ -n "$vre"   ]] && args+=(--check-regex "$vre")
  while IFS= read -r e; do [[ -n "$e" ]] && args+=(--extra "$e"); done \
    < <(tool_field "$id" '.github.extra[]?')

  install_github_release "${args[@]}"
  rc=$?
  case "$rc" in
    0)  report 20 "$id" ok "$version"
        # post_install：如 bat cache --build，让它认出 ~/.config/bat/themes
        if [[ -n "$post" && "$DRY_RUN" != 1 ]]; then
          debug "post_install: $post"
          if env PATH="$BIN_DIR:$PATH" bash -c "$post" >/dev/null 2>&1; then
            debug "$id：post_install OK"
          else
            warn "$id：post_install 失败（$post）—— 不致命"
          fi
        fi ;;
    10) report 20 "$id" skip "$version 已安装" ;;
    *)  if [[ "$required" == true ]]; then
          report 20 "$id" fail "必需项；重跑：./scripts/20-binaries.sh --only $id"
          RC=3
        else
          report 20 "$id" fail "可选项；重跑：./scripts/20-binaries.sh --only $id"
          [[ "$RC" == 0 ]] && RC=2
        fi ;;
  esac
done

exit "$RC"
