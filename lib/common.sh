#!/usr/bin/env bash
# lib/common.sh —— 日志、run/sudo_run 包装、报告账本、manifest 查询
# 只被 source，不直接执行。

# 防重复 source
[[ -n "${_UW_COMMON_LOADED:-}" ]] && return 0
_UW_COMMON_LOADED=1

set -uo pipefail

# ── 路径 ────────────────────────────────────────────────────────
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
UW_CACHE="${UW_CACHE:-$HOME/.cache/ubuntu_workflow}"
UW_STATE="${UW_STATE:-$HOME/.config/ubuntu_workflow}"
UW_REPORT="$UW_CACHE/report.tsv"
UW_DOWNLOADS="$UW_CACHE/downloads"
UW_STAMPS="$UW_CACHE/steps"
UW_BACKUP_ROOT="$UW_STATE/backup"

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
OPT_DIR="${OPT_DIR:-$HOME/.local/opt}"
COMPLETION_DIR="${COMPLETION_DIR:-$HOME/.local/share/zsh/completions}"
MAN_DIR="${MAN_DIR:-$HOME/.local/share/man/man1}"

# ── 全局开关（bootstrap.sh 会 export 覆盖）──────────────────────
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"
VERBOSE="${VERBOSE:-0}"
NO_SUDO="${NO_SUDO:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
PROFILE="${PROFILE:-desktop}"

# ── 颜色（非 tty 或 NO_COLOR 时自动关掉）────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m';  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m';  C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m';  C_MAG=$'\033[35m'; C_CYA=$'\033[36m'
else
  C_RESET=; C_DIM=; C_BOLD=; C_RED=; C_GRN=; C_YEL=; C_BLU=; C_MAG=; C_CYA=
fi

# ── 日志 ────────────────────────────────────────────────────────
log()   { printf '%s\n' "$*"; }
info()  { printf '%s▸%s %s\n'  "$C_BLU" "$C_RESET" "$*"; }
ok()    { printf '%s✓%s %s\n'  "$C_GRN" "$C_RESET" "$*"; }
skip()  { printf '%s·%s %s\n'  "$C_DIM" "$C_RESET" "${C_DIM}$*${C_RESET}"; }
warn()  { printf '%s!%s %s\n'  "$C_YEL" "$C_RESET" "$*" >&2; }
err()   { printf '%s✗%s %s\n'  "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
debug() { [[ "$VERBOSE" == 1 ]] && printf '%s  %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; return 0; }

hr()      { printf '%s%s%s\n' "$C_DIM" "────────────────────────────────────────────────────────────" "$C_RESET"; }
section() { printf '\n%s%s%s\n' "$C_BOLD$C_CYA" "$*" "$C_RESET"; hr; }

# ── 命令执行（--dry-run 在这一层实现）───────────────────────────
# run 和 sudo_run 是唯二执行外部副作用命令的地方。
run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  %s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  debug "run: $*"
  "$@"
}

# ★ 全仓库唯一出现 sudo 的地方。
#   `grep -rn sudo scripts/` 应当零命中 —— 这是可以 grep 审计的不变量。
sudo_run() {
  if [[ "$NO_SUDO" == 1 ]]; then
    warn "跳过（--no-sudo）：$*"
    return 70
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  sudo %s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  if [[ $EUID -eq 0 ]]; then
    debug "run(root): $*"
    "$@"
  else
    debug "sudo: $*"
    sudo "$@"
  fi
}

# 提前拿 sudo 凭据并起后台 keepalive —— 用户只在可预期的时刻输一次密码，
# 而不是在跑到一半时被突然弹出的提示打断。
_UW_SUDO_KEEPALIVE_PID=""
sudo_prime() {
  [[ "$NO_SUDO" == 1 || "$DRY_RUN" == 1 || $EUID -eq 0 ]] && return 0
  command -v sudo >/dev/null 2>&1 || { warn "没有 sudo，需要提权的步骤会被跳过"; NO_SUDO=1; return 0; }
  info "接下来的步骤需要 sudo（apt / snap / chsh）。请输入密码，全程只问这一次。"
  if ! sudo -v; then
    warn "拿不到 sudo 凭据 —— 转为 --no-sudo 模式继续"
    NO_SUDO=1
    return 0
  fi
  ( while true; do sleep 50; sudo -n true 2>/dev/null || exit; done ) &
  _UW_SUDO_KEEPALIVE_PID=$!
  trap 'sudo_release' EXIT
}
sudo_release() {
  [[ -n "$_UW_SUDO_KEEPALIVE_PID" ]] && kill "$_UW_SUDO_KEEPALIVE_PID" 2>/dev/null
  _UW_SUDO_KEEPALIVE_PID=""
}

# ── 报告账本 ────────────────────────────────────────────────────
# 每个单元的结果一行，供 99-summary.sh 和 agent 消费。
report_init() {
  mkdir -p "$UW_CACHE" "$UW_DOWNLOADS" "$UW_STAMPS"
  [[ -f "$UW_REPORT" ]] || printf '# timestamp\tstep\tunit\tstatus\tdetail\n' > "$UW_REPORT"
}
# report <step> <unit> <status: ok|skip|fail|na> <detail...>
report() {
  local step="$1" unit="$2" status="$3"; shift 3
  local detail="$*"
  mkdir -p "$UW_CACHE"
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -Is)" "$step" "$unit" "$status" "${detail//$'\t'/ }" >> "$UW_REPORT"
}

# ── 内容哈希 stamp（给不可版本化的步骤用）───────────────────────
stamp_path()   { printf '%s/%s.stamp' "$UW_STAMPS" "$1"; }
stamp_current(){ # stamp_current <name> <path...>  -> 打印输入的哈希
  local name="$1"; shift
  { for p in "$@"; do
      [[ -e "$p" ]] && find "$p" -type f -exec sha256sum {} + 2>/dev/null | sort -k2
    done; } | sha256sum | cut -d' ' -f1
}
stamp_matches() { # stamp_matches <name> <hash>
  local f; f="$(stamp_path "$1")"
  [[ "$FORCE" == 1 ]] && return 1
  [[ -f "$f" ]] && [[ "$(cat "$f" 2>/dev/null)" == "$2" ]]
}
stamp_write() {
  [[ "$DRY_RUN" == 1 ]] && return 0
  mkdir -p "$UW_STAMPS"; printf '%s\n' "$2" > "$(stamp_path "$1")"
}

# ── 架构变量（URL 模板用）───────────────────────────────────────
uw_detect_arch() {
  local m; m="$(uname -m)"
  case "$m" in
    x86_64|amd64)
      ARCH=x86_64; GO_ARCH=amd64; NODE_ARCH=x64
      RUST_TRIPLE=x86_64-unknown-linux-gnu
      RUST_TRIPLE_MUSL=x86_64-unknown-linux-musl ;;
    aarch64|arm64)
      ARCH=aarch64; GO_ARCH=arm64; NODE_ARCH=arm64
      RUST_TRIPLE=aarch64-unknown-linux-gnu
      RUST_TRIPLE_MUSL=aarch64-unknown-linux-musl ;;
    *) die "不支持的架构：$m（本仓库只在 x86_64 上验证过，aarch64 大体可用）" ;;
  esac
  export ARCH GO_ARCH NODE_ARCH RUST_TRIPLE RUST_TRIPLE_MUSL
}

# ── 模板展开 ────────────────────────────────────────────────────
# {version} {v} {arch} {go_arch} {node_arch} {rust_triple} {rust_triple_musl}
# 以及 $HOME / $BIN_DIR / $OPT_DIR / $COMPLETION_DIR / $MAN_DIR / $DEST_CJK
uw_tmpl() {
  local s="$1" version="${2:-}"
  s="${s//\{version\}/$version}"
  s="${s//\{v\}/v$version}"
  s="${s//\{arch\}/$ARCH}"
  s="${s//\{go_arch\}/$GO_ARCH}"
  s="${s//\{node_arch\}/$NODE_ARCH}"
  s="${s//\{rust_triple_musl\}/$RUST_TRIPLE_MUSL}"
  s="${s//\{rust_triple\}/$RUST_TRIPLE}"
  s="${s//\$COMPLETION_DIR/$COMPLETION_DIR}"
  s="${s//\$MAN_DIR/$MAN_DIR}"
  s="${s//\$BIN_DIR/$BIN_DIR}"
  s="${s//\$OPT_DIR/$OPT_DIR}"
  s="${s//\$DEST_CJK/${DEST_CJK:-}}"
  s="${s//\$HOME/$HOME}"
  printf '%s' "$s"
}

# ── manifest 查询 ───────────────────────────────────────────────
UW_TOOLS_JSON="$UW_ROOT/manifest/tools.json"
UW_PLUGINS_JSON="$UW_ROOT/manifest/zsh-plugins.json"
UW_FONTS_JSON="$UW_ROOT/manifest/fonts.json"

need_jq() { command -v jq >/dev/null 2>&1 || die "需要 jq。先跑 ./scripts/00-preflight.sh"; }

# 当前 profile 包含哪些 group
profile_groups() {
  need_jq
  jq -r --arg p "$PROFILE" '.profiles[$p][]?' "$UW_TOOLS_JSON"
}

# 列出当前 profile 内的 tool id。可选 --only / --method 过滤。
# tools_in_profile [method]
tools_in_profile() {
  need_jq
  local method="${1:-}"
  local groups; groups="$(profile_groups | jq -R . | jq -sc .)"
  jq -r --argjson g "$groups" --arg m "$method" '
    .tools[]
    | select(.group as $x | $g | index($x))
    | select($m == "" or .method == $m)
    | .id' "$UW_TOOLS_JSON"
}

tool_field() { # tool_field <id> <jq-path>
  need_jq
  jq -r --arg id "$1" ".tools[] | select(.id==\$id) | $2 // empty" "$UW_TOOLS_JSON"
}

# ── 版本探测：必须绕开 shell 函数/别名 ──────────────────────────
# ★ 这是全仓库最容易搞错的一点。
#   `command -v rg` 在 Claude Code 里会成功，因为 harness 注入了一个名为 rg
#   的 shell *函数*；用户的 .zshrc 又给 cat/find/grep/top 加了别名。
#   所以一律用 `type -P`（bash builtin，只查 PATH），版本命令跑在干净环境里。
uw_which() { # 解析真实二进制路径，忽略函数/别名/builtin
  PATH="$BIN_DIR:$OPT_DIR/neovim/bin:$OPT_DIR/node20/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/snap/bin" \
    type -P "$1" 2>/dev/null
}

uw_probe_version() { # uw_probe_version '<cmd>' '<regex>'  -> 打印捕获组 1
  local cmd="$1" re="$2" out
  out="$(env -i \
        HOME="$HOME" \
        PATH="$BIN_DIR:$OPT_DIR/neovim/bin:$OPT_DIR/node20/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/snap/bin" \
        LC_ALL=C \
        bash --noprofile --norc -c "$cmd" 2>&1)" || true
  [[ -z "$out" ]] && return 1
  printf '%s\n' "$out" | sed -nE "s/.*${re}.*/\1/p" | head -1 | grep -q . && \
    printf '%s\n' "$out" | sed -nE "s/.*${re}.*/\1/p" | head -1
}

# ── 交互 ────────────────────────────────────────────────────────
confirm() { # confirm "问题" [默认 y|n]
  local q="$1" def="${2:-n}" ans
  [[ "$ASSUME_YES" == 1 ]] && return 0
  [[ ! -t 0 ]] && { warn "非交互环境，按默认值 '$def' 处理：$q"; [[ "$def" == y ]]; return; }
  local hint="[y/N]"; [[ "$def" == y ]] && hint="[Y/n]"
  read -r -p "$(printf '%s?%s %s %s ' "$C_YEL" "$C_RESET" "$q" "$hint")" ans
  ans="${ans:-$def}"
  [[ "$ans" =~ ^[Yy] ]]
}

# ── 环境探测 ────────────────────────────────────────────────────
is_headless() { [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" && -z "${XDG_SESSION_TYPE:-}" ]]; }

# 字体是否真的可用。
# ★ 不能用 `fc-list : family | grep`：fontconfig 报的是缩写族名
#   （"IosevkaTermSlab NF" / "NFM"），跟 ghostty config 里写的全名
#   "IosevkaTermSlab Nerd Font Mono" 对不上，会误报缺失。
#   fc-match 才是语义正确的检查：「按这个名字要，实际拿到的是不是它」。
#   要不到时 fontconfig 会回落到 DejaVu Sans，一眼可辨。
font_available() {
  local fam="$1"
  command -v fc-match >/dev/null 2>&1 || return 2
  fc-match "$fam" 2>/dev/null | command grep -qiF "\"$fam\""
}
is_wsl()      { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }
is_container() { [[ -f /.dockerenv ]] || grep -qE 'docker|lxc|containerd' /proc/1/cgroup 2>/dev/null; }
has_snap()    { command -v snap >/dev/null 2>&1; }
