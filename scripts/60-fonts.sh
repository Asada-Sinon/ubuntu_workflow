#!/usr/bin/env bash
# 60-fonts —— 从上游下载字体（不进版本库：源机器上共 1.6 GB）
#
# 默认 minimal：只装 ghostty config 和 fontconfig 规则真正引用的两款。
# --fonts full 装全部 7 款（约 1.6 GB）。
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/fetch.sh"
uw_detect_arch
report_init
need_jq

SET="${FONT_SET:-minimal}"
case "$SET" in minimal|full) ;; *) warn "未知字体集 '$SET'，按 minimal 处理"; SET=minimal ;; esac

RC=0
NF_TAG="$(jq -r '.nerd_fonts_release' "$UW_FONTS_JSON")"
DEST_NERD="$(uw_tmpl "$(jq -r '.dest_nerd' "$UW_FONTS_JSON")")"
DEST_CJK="$(uw_tmpl "$(jq -r '.dest_cjk' "$UW_FONTS_JSON")")"
export DEST_CJK

mapfile -t WANT < <(jq -r --arg s "$SET" '.sets[$s][]' "$UW_FONTS_JSON")
TOTAL_MB="$(jq -r --argjson w "$(printf '%s\n' "${WANT[@]}" | jq -R . | jq -sc .)" \
  '[.fonts[] | select(.id as $i | $w | index($i)) | .approx_mb] | add' "$UW_FONTS_JSON")"

info "字体集 '$SET'：${#WANT[@]} 款，约 ${TOTAL_MB}MB"
[[ "$SET" == minimal ]] && info "（full 集另含 JetBrainsMono/Meslo/Monaspace/FiraCode/CodeNewRoman，用 --fonts full）"

[[ "$DRY_RUN" == 1 ]] || mkdir -p "$DEST_NERD" "$DEST_CJK"

for id in "${WANT[@]}"; do
  kind="$(jq -r --arg i "$id" '.fonts[]|select(.id==$i)|.kind' "$UW_FONTS_JSON")"
  family="$(jq -r --arg i "$id" '.fonts[]|select(.id==$i)|.family' "$UW_FONTS_JSON")"

  # 幂等：这个 family 已经能被 fontconfig 解析出来就跳过
  if [[ "$FORCE" != 1 && "$DRY_RUN" != 1 ]] && font_available "$family"; then
    skip "$id（$family 已可用）"
    report 60 "font:$id" skip "$family"
    continue
  fi

  case "$kind" in
    nerd_font)
      asset="$(jq -r --arg i "$id" '.fonts[]|select(.id==$i)|.asset' "$UW_FONTS_JSON")"
      url="https://github.com/ryanoasis/nerd-fonts/releases/download/$NF_TAG/$asset"
      if [[ "$DRY_RUN" == 1 ]]; then
        if uw_url_alive "$url"; then
          printf '%s  DRY  %-16s %s%s\n' "$C_DIM" "$id" "$url" "$C_RESET"
        else
          err "$id：URL 不可达 $url"; RC=2
        fi
        continue
      fi
      if archive="$(_uw_download "$url")"; then
        outdir="$DEST_NERD/$id"
        mkdir -p "$outdir"
        # Nerd Font zip 里混着 .ttf/.otf 和一堆 README/LICENSE，只要字体
        if unzip -q -o "$archive" -d "$outdir" -x '*.md' '*.txt' 'LICENSE*' 'README*' 2>/dev/null; then
          n="$(find "$outdir" -type f \( -name '*.ttf' -o -name '*.otf' \) | wc -l)"
          ok "$id（$n 个字体文件）"
          report 60 "font:$id" ok "$n files"
        else
          err "$id：解包失败"
          report 60 "font:$id" fail "unzip 失败"
          RC=2
        fi
      else
        err "$id：下载失败 $url"
        report 60 "font:$id" fail "下载失败"
        RC=2
      fi
      ;;
    url)
      dest="$(uw_tmpl "$(jq -r --arg i "$id" '.fonts[]|select(.id==$i)|.dest' "$UW_FONTS_JSON")")"
      [[ "$DRY_RUN" == 1 ]] || mkdir -p "$dest"
      nok=0; nfail=0
      while IFS= read -r u; do
        [[ -z "$u" ]] && continue
        if [[ "$DRY_RUN" == 1 ]]; then
          uw_url_alive "$u" && printf '%s  DRY  %-16s %s%s\n' "$C_DIM" "$id" "$u" "$C_RESET" \
                            || { err "$id：URL 不可达 $u"; RC=2; }
          continue
        fi
        if f="$(_uw_download "$u")"; then
          cp "$f" "$dest/$(basename "${u%%\?*}")"; nok=$((nok+1))
        else
          nfail=$((nfail+1))
        fi
      done < <(jq -r --arg i "$id" '.fonts[]|select(.id==$i)|.urls[]' "$UW_FONTS_JSON")
      [[ "$DRY_RUN" == 1 ]] && continue
      if [[ "$nok" -gt 0 ]]; then
        ok "$id（$nok 个字体文件）"
        report 60 "font:$id" ok "$nok files"
      else
        err "$id：全部下载失败"
        report 60 "font:$id" fail "下载失败"
        RC=2
      fi
      ;;
  esac
done

# ── 刷新字体缓存 ────────────────────────────────────────────────
if [[ "$DRY_RUN" != 1 ]]; then
  if command -v fc-cache >/dev/null 2>&1; then
    run fc-cache -f >/dev/null 2>&1 && ok "fc-cache 已刷新"
    report 60 fc-cache ok ""
    # 验证：只查 ghostty config 真正引用的那两款
    for fam in "IosevkaTermSlab Nerd Font Mono" "LXGW WenKai Mono"; do
      if font_available "$fam"; then
        ok "字体可解析：$fam"
      else
        warn "按名字要不到：$fam —— fontconfig 会回落到别的字体（终端里会看到豆腐块）"
        [[ "$RC" == 0 ]] && RC=2
      fi
    done
  else
    warn "没有 fc-cache（缺 fontconfig 包），字体不会被系统认出来"
    report 60 fc-cache fail "缺 fontconfig"
    [[ "$RC" == 0 ]] && RC=2
  fi
  info "已开着的终端要重启才认新字体"
fi

exit "$RC"
