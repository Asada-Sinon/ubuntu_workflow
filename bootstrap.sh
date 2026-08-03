#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  ubuntu_workflow —— 唯一入口
#
#  用法：
#    ./bootstrap.sh --dry-run              先看计划 + 查链接腐烂（推荐第一步）
#    ./bootstrap.sh                        按 desktop profile 全装
#    ./bootstrap.sh --profile minimal      只装终端，不碰 GUI
#    ./bootstrap.sh --no-sudo              零提权，全装在 ~ 下
#    ./bootstrap.sh --only 20,50           只跑指定步骤
#    ./bootstrap.sh --skip 70              跳过指定步骤
#
#  退出码（给 agent 分支用，不用解析散文）：
#    0  全好
#    1  用法错 / preflight 失败
#    2  有 required:false 的项失败
#    3  有 required:true  的项失败
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

UW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UW_ROOT
# shellcheck source=lib/common.sh
source "$UW_ROOT/lib/common.sh"

PROFILE=desktop
ONLY=""
SKIP=""
FONT_SET=""

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

选项：
  --profile <minimal|desktop>  默认 desktop
  --dry-run                    只打印计划，并对每个 URL 发 HEAD 请求
  --yes                        所有确认一律 yes（无人值守）
  --only  <steps>              逗号分隔的步骤号，如 20,50
  --skip  <steps>              逗号分隔的步骤号
  --no-sudo                    跳过所有需要提权的步骤
  --fonts <minimal|full>       字体集，默认 minimal
  --force                      忽略「已安装」判断，全部重装
  --verbose                    打印调试信息
  -h, --help                   本帮助
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)  PROFILE="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1;    shift   ;;
    --yes|-y)   ASSUME_YES=1; shift   ;;
    --only)     ONLY="$2";    shift 2 ;;
    --skip)     SKIP="$2";    shift 2 ;;
    --no-sudo)  NO_SUDO=1;    shift   ;;
    --fonts)    FONT_SET="$2";shift 2 ;;
    --force)    FORCE=1;      shift   ;;
    --verbose)  VERBOSE=1;    shift   ;;
    -h|--help)  usage; exit 0 ;;
    *) err "未知参数：$1"; usage; exit 1 ;;
  esac
done

case "$PROFILE" in minimal|desktop) ;; *) err "--profile 只能是 minimal 或 desktop"; exit 1 ;; esac
export PROFILE DRY_RUN FORCE VERBOSE NO_SUDO ASSUME_YES FONT_SET

uw_detect_arch
report_init

# ── 步骤表 ──────────────────────────────────────────────────────
# 号码 : 脚本 : 是否需要提权 : 描述
STEPS=(
  "00:00-preflight.sh:0:环境断言 + 装 jq + 打印计划"
  "10:10-apt.sh:1:批量 apt 装系统基础包"
  "20:20-binaries.sh:0:静态二进制 → ~/.local/bin"
  "30:30-runtimes.sh:0:node20 + uv + uv 托管 python"
  "40:40-zsh.sh:1:zsh 插件 + 设为登录 shell"
  "50:50-dotfiles.sh:0:落地 home/ 下的配置"
  "60:60-fonts.sh:0:下载字体 + fc-cache"
  "70:70-desktop.sh:1:Ghostty + Termius + GNOME Terminal 配色"
  "99:99-summary.sh:0:汇总报告 + 手动步骤清单"
)

step_selected() {
  local n="$1"
  if [[ -n "$ONLY" ]]; then
    [[ ",$ONLY," == *",$n,"* ]] || return 1
  fi
  if [[ -n "$SKIP" ]]; then
    [[ ",$SKIP," == *",$n,"* ]] && return 1
  fi
  return 0
}

# ── 打印计划 ────────────────────────────────────────────────────
section "ubuntu_workflow"
printf '  仓库      %s\n' "$UW_ROOT"
printf '  profile   %s\n' "$PROFILE"
printf '  架构      %s\n' "$ARCH"
printf '  字体      %s\n' "${FONT_SET:-minimal}"
[[ "$DRY_RUN" == 1 ]] && printf '  %s模式      DRY-RUN（不写任何文件）%s\n' "$C_YEL" "$C_RESET"
[[ "$NO_SUDO" == 1 ]] && printf '  %s模式      NO-SUDO（跳过所有提权步骤）%s\n' "$C_YEL" "$C_RESET"
echo

declare -a PLAN=()
NEEDS_SUDO=0
for s in "${STEPS[@]}"; do
  IFS=: read -r num script sudo_flag desc <<< "$s"
  if step_selected "$num"; then
    if [[ "$sudo_flag" == 1 && "$NO_SUDO" == 1 ]]; then
      printf '  %s%s  %-18s %s（--no-sudo，跳过）%s\n' "$C_DIM" "$num" "$script" "$desc" "$C_RESET"
      continue
    fi
    [[ "$sudo_flag" == 1 ]] && NEEDS_SUDO=1
    local_mark=" "; [[ "$sudo_flag" == 1 ]] && local_mark="${C_YEL}sudo${C_RESET}"
    printf '  %s  %-18s %-42s %b\n' "$num" "$script" "$desc" "$local_mark"
    PLAN+=("$s")
  else
    printf '  %s%s  %-18s %s（跳过）%s\n' "$C_DIM" "$num" "$script" "$desc" "$C_RESET"
  fi
done
echo

[[ ${#PLAN[@]} -eq 0 ]] && { warn "没有选中任何步骤"; exit 1; }

# ── 一次性拿 sudo ───────────────────────────────────────────────
if [[ "$NEEDS_SUDO" == 1 && "$DRY_RUN" != 1 ]]; then
  sudo_prime
  export NO_SUDO
fi

# ── 逐步执行 ────────────────────────────────────────────────────
# 刻意不用 set -e：某个工具的 release asset 改名了，不该让整个 bootstrap
# 在 40% 处暴毙。每步在子 shell 里跑，退出码收集起来最后汇总。
FAIL_REQUIRED=0
FAIL_OPTIONAL=0

for s in "${PLAN[@]}"; do
  IFS=: read -r num script sudo_flag desc <<< "$s"
  section "[$num] $desc"
  bash "$UW_ROOT/scripts/$script"
  rc=$?
  case "$rc" in
    0)  ;;
    2)  FAIL_OPTIONAL=1; warn "[$num] 有可选项失败" ;;
    3)  FAIL_REQUIRED=1; err  "[$num] 有必需项失败" ;;
    1)  if [[ "$num" == 00 ]]; then
          err "preflight 失败，中止。"
          exit 1
        fi
        FAIL_REQUIRED=1; err "[$num] 失败（rc=$rc）" ;;
    *)  FAIL_OPTIONAL=1; warn "[$num] 非预期退出码 $rc" ;;
  esac
done

echo
if   [[ "$FAIL_REQUIRED" == 1 ]]; then err "完成，但有必需项失败。跑 ./verify.sh 看细节。"; exit 3
elif [[ "$FAIL_OPTIONAL" == 1 ]]; then warn "完成，有可选项失败（不影响核心环境）。"; exit 2
else ok "全部完成。"; exit 0
fi
