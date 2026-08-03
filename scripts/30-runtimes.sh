#!/usr/bin/env bash
# 30-runtimes —— url_archive 类工具（node20 / neovim）+ uv 托管的 Python
# 顺序有依赖：uv 必须先在 PATH 上（20-binaries 装的），才能 uv python install。
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/fetch.sh"
uw_detect_arch
report_init
need_jq

RC=0
mkdir -p "$OPT_DIR" "$BIN_DIR"

# ── url_archive：整个目录树 ─────────────────────────────────────
mapfile -t IDS < <(tools_in_profile url_archive)
for id in "${IDS[@]}"; do
  version="$(tool_field "$id" '.version')"
  required="$(tool_field "$id" '.required')"
  url="$(uw_tmpl "$(tool_field "$id" '.url_archive.url')" "$version")"
  dest="$(uw_tmpl "$(tool_field "$id" '.url_archive.dest')" "$version")"
  strip="$(tool_field "$id" '.url_archive.strip')"
  vcmd="$(uw_tmpl "$(tool_field "$id" '.verify.cmd')" "$version")"
  vre="$(tool_field "$id" '.verify.regex')"

  args=(--name "$id" --version "$version" --url "$url" --dest "$dest")
  [[ -n "$strip" ]] && args+=(--strip "$strip")
  [[ -n "$vcmd"  ]] && args+=(--check "$vcmd")
  [[ -n "$vre"   ]] && args+=(--check-regex "$vre")
  while IFS= read -r b; do [[ -n "$b" ]] && args+=(--link-bin "$b"); done \
    < <(tool_field "$id" '.url_archive.link_bin[]?')

  install_archive_to_dir "${args[@]}"
  rc=$?
  case "$rc" in
    0)  report 30 "$id" ok "$version" ;;
    10) report 30 "$id" skip "$version 已安装" ;;
    *)  if [[ "$required" == true ]]; then
          report 30 "$id" fail "必需项；重跑：./scripts/30-runtimes.sh"
          RC=3
        else
          report 30 "$id" fail "可选项"
          [[ "$RC" == 0 ]] && RC=2
        fi ;;
  esac
done

# node20 不软链进 ~/.local/bin —— .zshrc 直接把它的 bin/ 加进 PATH，
# 这样 npm 全局装的东西（prefix 落在 node20 里）也自动可用。
if [[ -x "$OPT_DIR/node20/bin/node" ]]; then
  debug "node20 由 .zshrc 的 PATH 暴露，不建软链"
fi

# ── uv 托管的 Python ────────────────────────────────────────────
mapfile -t PYIDS < <(tools_in_profile uv_python)
for id in "${PYIDS[@]}"; do
  spec="$(tool_field "$id" '.uv_python.spec')"
  uv_bin="$(uw_which uv)"
  if [[ -z "$uv_bin" ]]; then
    warn "uv 不在 PATH 上，跳过 uv python install（先让 20-binaries 装上 uv）"
    report 30 "$id" fail "uv 缺失"
    [[ "$RC" == 0 ]] && RC=2
    continue
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  %s python install %s%s\n' "$C_DIM" "$uv_bin" "$spec" "$C_RESET"
    continue
  fi
  if "$uv_bin" python find "$spec" >/dev/null 2>&1 && [[ "$FORCE" != 1 ]]; then
    skip "uv python $spec 已安装"
    report 30 "$id" skip "$spec"
  elif "$uv_bin" python install "$spec"; then
    ok "uv python $spec"
    report 30 "$id" ok "$spec"
  else
    warn "uv python install $spec 失败（不致命，系统 python3 仍可用）"
    report 30 "$id" fail "$spec"
    [[ "$RC" == 0 ]] && RC=2
  fi
done

exit "$RC"
