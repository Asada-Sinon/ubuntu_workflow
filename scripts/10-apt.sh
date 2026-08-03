#!/usr/bin/env bash
# 10-apt —— 一次 update + 一次批量 install。全程只花掉一次 sudo。
set -uo pipefail
UW_ROOT="${UW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$UW_ROOT/lib/common.sh"
uw_detect_arch
report_init
need_jq

if [[ "$NO_SUDO" == 1 ]]; then
  warn "--no-sudo：跳过所有 apt 安装"
  warn "缺失的系统包（zsh / tmux / git / fontconfig …）需要你自己装"
  report 10 apt skip "--no-sudo"
  exit 0
fi

RC=0

# 把 profile 内所有 method=apt 的包合成一个列表，一次装完
mapfile -t APT_IDS < <(tools_in_profile apt)
[[ ${#APT_IDS[@]} -eq 0 ]] && { skip "本 profile 没有 apt 包"; exit 0; }

PKGS=()
for id in "${APT_IDS[@]}"; do
  while IFS= read -r p; do [[ -n "$p" ]] && PKGS+=("$p"); done < <(tool_field "$id" '.apt.packages[]?')
done

info "要装 ${#PKGS[@]} 个 apt 包：${PKGS[*]}"

if [[ "$DRY_RUN" == 1 ]]; then
  printf '%s  DRY  sudo apt-get update%s\n' "$C_DIM" "$C_RESET"
  printf '%s  DRY  sudo apt-get install -y %s%s\n' "$C_DIM" "${PKGS[*]}" "$C_RESET"
  exit 0
fi

# 已经全装好了就别动 apt（apt-get update 很慢）
MISSING=()
for p in "${PKGS[@]}"; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "^install ok installed" || MISSING+=("$p")
done

if [[ ${#MISSING[@]} -eq 0 && "$FORCE" != 1 ]]; then
  skip "apt 包已全部安装（${#PKGS[@]} 个）"
  report 10 apt skip "已全部安装"
  exit 0
fi

info "缺 ${#MISSING[@]} 个：${MISSING[*]}"

export DEBIAN_FRONTEND=noninteractive
if ! sudo_run apt-get update -qq; then
  warn "apt-get update 失败（源不可达？锁被占？）—— 仍尝试安装"
fi

if sudo_run apt-get install -y -qq "${MISSING[@]}"; then
  ok "apt 安装完成（${#MISSING[@]} 个包）"
  report 10 apt ok "${MISSING[*]}"
else
  err "apt 安装失败。逐个重试以定位问题："
  for p in "${MISSING[@]}"; do
    if sudo_run apt-get install -y -qq "$p" >/dev/null 2>&1; then
      ok "  $p"
      report 10 "apt:$p" ok ""
    else
      err "  $p 装不上"
      report 10 "apt:$p" fail "apt-get install 失败"
      # zsh 是唯一真正必需的
      [[ "$p" == zsh ]] && RC=3
    fi
  done
  [[ "$RC" == 0 ]] && RC=2
fi

exit "$RC"
