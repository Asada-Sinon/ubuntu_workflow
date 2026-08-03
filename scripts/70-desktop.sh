#!/usr/bin/env bash
# 70-desktop —— Ghostty（snap）+ Termius（vendor deb）+ GNOME Terminal 配色
# 需要提权，且需要图形会话。headless / 容器 / WSL 会整步跳过。
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/fetch.sh"
uw_detect_arch
report_init
need_jq

RC=0

if is_headless && [[ "$DRY_RUN" != 1 ]]; then
  warn "没有图形会话 —— 跳过整个 70-desktop"
  report 70 desktop skip "headless"
  exit 0
fi
if is_container || is_wsl; then
  warn "容器/WSL 环境 —— 跳过整个 70-desktop"
  report 70 desktop skip "container/wsl"
  exit 0
fi

# ── snap 类工具（Ghostty）───────────────────────────────────────
mapfile -t SNAP_IDS < <(tools_in_profile snap)
for id in "${SNAP_IDS[@]}"; do
  name="$(tool_field "$id" '.snap.name')"
  classic="$(tool_field "$id" '.snap.classic')"
  publisher="$(tool_field "$id" '.snap.publisher')"
  version="$(tool_field "$id" '.version')"
  vcmd="$(tool_field "$id" '.verify.cmd')"
  vre="$(tool_field "$id" '.verify.regex')"

  if ! has_snap; then
    warn "$id：系统没有 snapd，跳过。（Ghostty 官方不发 deb，需要的话自行编译）"
    report 70 "$id" skip "无 snapd"
    continue
  fi

  have="$(uw_probe_version "$vcmd" "$vre" || true)"
  if [[ -n "$have" && "$FORCE" != 1 ]]; then
    skip "$id $have 已安装"
    report 70 "$id" skip "$have"
    continue
  fi

  args=(snap install "$name")
  [[ "$classic" == true ]] && args+=(--classic)

  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  sudo %s%s\n' "$C_DIM" "${args[*]}" "$C_RESET"
    continue
  fi

  # classic confinement = 全系统访问权限。第三方打包，明确告知后再装。
  if [[ "$classic" == true ]]; then
    warn "$id 是 snap classic 包（打包者：$publisher，非官方）。"
    warn "classic confinement 意味着它对整个系统有完全访问权限。"
    if ! confirm "安装 $id？" y; then
      info "跳过 $id"
      report 70 "$id" skip "用户拒绝"
      continue
    fi
  fi

  if sudo_run "${args[@]}"; then
    ok "$id 已安装"
    report 70 "$id" ok "snap"
  else
    warn "$id 安装失败（可选项）"
    report 70 "$id" fail "snap install 失败"
    [[ "$RC" == 0 ]] && RC=2
  fi
done

# ── vendor deb（Termius）───────────────────────────────────────
mapfile -t DEB_IDS < <(tools_in_profile vendor_deb)
for id in "${DEB_IDS[@]}"; do
  url="$(tool_field "$id" '.vendor_deb.url')"
  pkg="$(tool_field "$id" '.vendor_deb.package')"
  followup="$(tool_field "$id" '.manual_followup')"

  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed" && [[ "$FORCE" != 1 ]]; then
    ver="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)"
    skip "$id $ver 已安装"
    report 70 "$id" skip "$ver"
    [[ -n "$followup" ]] && info "  提醒：$followup"
    continue
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    uw_url_alive "$url" && printf '%s  DRY  下载并 dpkg -i %s%s\n' "$C_DIM" "$url" "$C_RESET" \
                        || { err "$id：URL 不可达 $url"; RC=2; }
    continue
  fi

  if ! deb="$(_uw_download "$url")"; then
    err "$id：下载失败 $url"
    report 70 "$id" fail "下载失败"
    [[ "$RC" == 0 ]] && RC=2
    continue
  fi

  # dpkg -i 可能因缺依赖失败，apt-get -f install 补齐后再试一次
  if sudo_run dpkg -i "$deb" >/dev/null 2>&1 || \
     { sudo_run apt-get -y -f install >/dev/null 2>&1 && sudo_run dpkg -i "$deb" >/dev/null 2>&1; }; then
    ver="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo '?')"
    ok "$id $ver 已安装"
    report 70 "$id" ok "$ver"
    # Termius 的 postinst 自己写 apt 源和 keyring，之后由 apt 自动更新
    [[ -n "$followup" ]] && { echo; warn "手动步骤：$followup"; }
  else
    warn "$id 安装失败（可选项）"
    report 70 "$id" fail "dpkg -i 失败"
    [[ "$RC" == 0 ]] && RC=2
  fi
done

# ── GNOME Terminal 配色（破坏性，必须问）───────────────────────
DCONF_FILE="$UW_ROOT/desktop/gnome-terminal.dconf"
if [[ -f "$DCONF_FILE" ]] && command -v dconf >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  dconf load /org/gnome/terminal/ < %s%s\n' "$C_DIM" "$DCONF_FILE" "$C_RESET"
  elif ! gsettings list-schemas 2>/dev/null | grep -q org.gnome.Terminal; then
    skip "没装 GNOME Terminal，跳过配色导入"
    report 70 gnome-terminal skip "未安装"
  else
    warn "dconf load 会替换 GNOME Terminal 的【全部】profile，不只是新增一个。"
    if confirm "导入 GNOME Terminal 的 Catppuccin 配色？（会先自动备份现有配置）" n; then
      bdir="$UW_STATE/backup/$(date +%Y%m%dT%H%M%S)"
      mkdir -p "$bdir"
      dconf dump /org/gnome/terminal/ > "$bdir/gnome-terminal.dconf.bak" 2>/dev/null
      ok "已备份现有配置 → $bdir/gnome-terminal.dconf.bak"
      if dconf load /org/gnome/terminal/ < "$DCONF_FILE"; then
        ok "GNOME Terminal 配色已导入"
        report 70 gnome-terminal ok "已导入（备份在 $bdir）"
      else
        warn "dconf load 失败（SSH 会话里没有 DBus？）"
        report 70 gnome-terminal fail "dconf load 失败"
        [[ "$RC" == 0 ]] && RC=2
      fi
    else
      info "跳过。想导入时执行：dconf load /org/gnome/terminal/ < $DCONF_FILE"
      report 70 gnome-terminal skip "用户拒绝"
    fi
  fi
fi

exit "$RC"
