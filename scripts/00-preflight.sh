#!/usr/bin/env bash
# 00-preflight —— 环境断言 + 确保 jq 可用 + 校验 manifest
# 这是唯一会在 10-apt 之外调 apt 的步骤（因为后面所有步骤都要 jq 解析 manifest）。
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/fetch.sh"
uw_detect_arch
report_init

RC=0

# ── OS ──────────────────────────────────────────────────────────
if command -v lsb_release >/dev/null 2>&1; then
  DISTRO="$(lsb_release -is 2>/dev/null)"; RELEASE="$(lsb_release -rs 2>/dev/null)"
else
  DISTRO="$(. /etc/os-release 2>/dev/null && printf '%s' "${NAME:-unknown}")"
  RELEASE="$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_ID:-?}")"
fi
info "系统：$DISTRO $RELEASE / $(uname -m) / kernel $(uname -r)"

if [[ "$DISTRO" != *Ubuntu* && "$DISTRO" != *Debian* ]]; then
  warn "本仓库只在 Ubuntu 22.04 上验证过，当前是 $DISTRO $RELEASE。"
  warn "apt 包名和 snap 可能对不上。要继续请确认。"
  confirm "仍然继续？" n || { report 00 os fail "$DISTRO $RELEASE"; exit 1; }
fi
report 00 os ok "$DISTRO $RELEASE $(uname -m)"

# ── 会话类型 ────────────────────────────────────────────────────
if is_headless; then
  info "检测到 headless（无 DISPLAY / WAYLAND_DISPLAY / XDG_SESSION_TYPE）"
  if [[ "$PROFILE" == desktop ]]; then
    warn "profile=desktop 但没有图形会话 —— GUI 步骤（Ghostty / Termius）会自动跳过"
  fi
  report 00 session ok headless
else
  report 00 session ok "${XDG_SESSION_TYPE:-x11}"
fi
is_wsl       && { info "检测到 WSL —— 70-desktop 会跳过"; report 00 wsl ok yes; }
is_container && { info "检测到容器 —— 70-desktop 会跳过"; report 00 container ok yes; }

# ── 网络 ────────────────────────────────────────────────────────
if curl -fsI --connect-timeout 10 --max-time 20 https://github.com >/dev/null 2>&1; then
  ok "网络可达 github.com"
  report 00 network ok github.com
else
  err "连不上 github.com。本仓库所有工具都从 GitHub releases 下载。"
  err "如果需要代理，先 export https_proxy=... 再重跑。"
  report 00 network fail "github.com 不可达"
  exit 1
fi

# ── 磁盘 ────────────────────────────────────────────────────────
AVAIL_MB="$(df -Pm "$HOME" | awk 'NR==2{print $4}')"
if [[ "${AVAIL_MB:-0}" -lt 2000 ]]; then
  err "$HOME 只剩 ${AVAIL_MB}MB，至少需要 2GB（full 字体集要 3GB+）"
  report 00 disk fail "${AVAIL_MB}MB"
  exit 1
fi
ok "磁盘剩余 ${AVAIL_MB}MB"
report 00 disk ok "${AVAIL_MB}MB"

# ── 基础命令 ────────────────────────────────────────────────────
for c in curl tar; do
  command -v "$c" >/dev/null 2>&1 || { err "缺少 $c，无法继续。sudo apt install -y $c"; exit 1; }
done

# ── jq：manifest 解析器，后面每一步都要 ────────────────────────
if command -v jq >/dev/null 2>&1; then
  ok "jq 已就绪（$(jq --version)）"
  report 00 jq skip "$(jq --version)"
else
  info "缺 jq —— 后续步骤全靠它解析 manifest"
  if [[ "$NO_SUDO" != 1 ]] && sudo_run apt-get install -y -qq jq >/dev/null 2>&1; then
    ok "jq 已装（apt）"
    report 00 jq ok "apt"
  else
    # 没有 sudo 也能活：用仓库自己的原语拉一个静态 jq 到 ~/.local/bin
    info "apt 走不通，改用静态二进制（~/.local/bin/jq）"
    mkdir -p "$BIN_DIR"
    if install_binary_from_url \
         --name jq --version 1.8.2 \
         --url "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-${GO_ARCH}" \
         --check 'jq --version' --check-regex '^jq-([0-9.]+)'; then
      report 00 jq ok "static"
    else
      err "装不上 jq。手动装一个再重跑：sudo apt install -y jq"
      report 00 jq fail "装不上"
      exit 1
    fi
    export PATH="$BIN_DIR:$PATH"
  fi
fi

# ── manifest 校验 ───────────────────────────────────────────────
for f in "$UW_TOOLS_JSON" "$UW_PLUGINS_JSON" "$UW_FONTS_JSON"; do
  if jq -e . "$f" >/dev/null 2>&1; then
    debug "manifest OK：$(basename "$f")"
  else
    err "manifest 解析失败：$f"
    report 00 manifest fail "$(basename "$f")"
    RC=1
  fi
done
[[ "$RC" == 0 ]] && { ok "manifest 全部可解析"; report 00 manifest ok "3 个文件"; }

# profile 必须存在
if ! jq -e --arg p "$PROFILE" '.profiles[$p]' "$UW_TOOLS_JSON" >/dev/null 2>&1; then
  err "manifest 里没有 profile '$PROFILE'"
  exit 1
fi

N_TOOLS="$(tools_in_profile | wc -l)"
info "profile '$PROFILE' 覆盖 $N_TOOLS 个工具，group：$(profile_groups | tr '\n' ' ')"

# ── 目录 ────────────────────────────────────────────────────────
if [[ "$DRY_RUN" != 1 ]]; then
  mkdir -p "$BIN_DIR" "$OPT_DIR" "$COMPLETION_DIR" "$MAN_DIR" \
           "$UW_CACHE" "$UW_DOWNLOADS" "$UW_STAMPS" "$UW_STATE" \
           "$HOME/.cache/zsh"
fi

exit "$RC"
