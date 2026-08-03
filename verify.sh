#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  verify.sh —— doctor。检查每一项是否真的到位。
#
#  ★ 核心约束：绝不相信当前 shell。
#
#  `command -v rg` 在 Claude Code 里会成功 —— harness 从
#  ~/.claude/shell-snapshots/ 注入了一个名为 rg 的 shell *函数*，
#  但 PATH 上根本没有 rg 二进制。用户的 .zshrc 又给
#  cat / find / grep / top 都加了别名。
#
#  所以这里一律用 `type -P`（bash builtin，只查 PATH，忽略函数、
#  别名、builtin），版本命令跑在 env -i 的干净环境里。
#  否则这个脚本会把一个残缺的环境自信地报成健康。
#
#  退出码：0 全好 · 2 有警告 · 3 有失败
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

UW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UW_ROOT
source "$UW_ROOT/lib/common.sh"

PROFILE=desktop
BRIEF=0
JSON=0
HYGIENE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)  PROFILE="$2"; shift 2 ;;
    --brief)    BRIEF=1;      shift   ;;
    --json)     JSON=1;       shift   ;;
    --hygiene)  HYGIENE_ONLY=1; shift ;;
    -h|--help)  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "未知参数：$1"; exit 1 ;;
  esac
done
export PROFILE

uw_detect_arch

N_OK=0; N_WARN=0; N_FAIL=0
declare -a ROWS=()

# row <status> <category> <item> <expected> <actual> <remedy>
row() {
  local st="$1"
  ROWS+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\t'"$5"$'\t'"${6:-}")
  case "$st" in
    OK)   N_OK=$((N_OK+1)) ;;
    WARN) N_WARN=$((N_WARN+1)) ;;
    FAIL) N_FAIL=$((N_FAIL+1)) ;;
  esac
}

# ════════════════════════════════════════════════════════════════
#  A. 仓库卫生（public 仓库，这一项也在 CI 里跑）
# ════════════════════════════════════════════════════════════════
check_hygiene() {
  # A1. git/gitconfig 里绝不能有身份
  if command -v git >/dev/null 2>&1; then
    if git config --file "$UW_ROOT/git/gitconfig" --get-regexp '^user\.' >/dev/null 2>&1; then
      row FAIL 仓库卫生 "git/gitconfig 身份" "无 [user]" "含 user.*" "删掉 git/gitconfig 里的 [user] 段"
    else
      row OK 仓库卫生 "git/gitconfig 身份" "无 [user]" "干净" ""
    fi
  fi

  # A2. 跟踪文件里不能有邮箱
  local files hits
  if command -v git >/dev/null 2>&1 && git -C "$UW_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    mapfile -t files < <(git -C "$UW_ROOT" ls-files)
  else
    mapfile -t files < <(cd "$UW_ROOT" && find . -type f -not -path './.git/*' | sed 's|^\./||')
  fi
  hits=""
  for f in "${files[@]}"; do
    [[ "$f" == *.example ]] && continue      # 示例文件里的 you@example.com 是刻意的
    [[ -f "$UW_ROOT/$f" ]] || continue
    if command grep -qIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$UW_ROOT/$f" 2>/dev/null; then
      # 白名单：github noreply / example.com 之类的占位
      if command grep -IoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$UW_ROOT/$f" 2>/dev/null \
         | command grep -qvE '(example\.com|users\.noreply\.github\.com|@[0-9]+x)'; then
        hits+="$f "
      fi
    fi
  done
  if [[ -n "$hits" ]]; then
    row FAIL 仓库卫生 "邮箱泄漏" "无真实邮箱" "$hits" "从这些文件里删掉邮箱"
  else
    row OK 仓库卫生 "邮箱泄漏" "无真实邮箱" "干净" ""
  fi

  # A3. 私钥
  # needle 由三段拼出来，免得本文件自己命中自己的检查
  local needle="-----BEGIN"' .*PRIVATE'" KEY-----"
  hits=""
  for f in "${files[@]}"; do
    [[ -f "$UW_ROOT/$f" ]] || continue
    command grep -qIE -- "$needle" "$UW_ROOT/$f" 2>/dev/null && hits+="$f "
  done
  if [[ -n "$hits" ]]; then
    row FAIL 仓库卫生 "私钥" "无" "$hits" "立刻删除并轮换密钥"
  else
    row OK 仓库卫生 "私钥" "无" "干净" ""
  fi

  # A4. 大文件（字体不该进仓库）
  local big
  big="$(cd "$UW_ROOT" && find . -type f -not -path './.git/*' -size +1M -printf '%p ' 2>/dev/null)"
  if [[ -n "$big" ]]; then
    row WARN 仓库卫生 "大文件 >1MB" "无" "$big" "字体/归档应由脚本下载，不进仓库"
  else
    row OK 仓库卫生 "大文件 >1MB" "无" "干净" ""
  fi
}

# ════════════════════════════════════════════════════════════════
#  B. 二进制存在 + 版本
# ════════════════════════════════════════════════════════════════
check_tools() {
  need_jq
  local ids id version vcmd vre required have bin method
  mapfile -t ids < <(tools_in_profile)
  for id in "${ids[@]}"; do
    method="$(tool_field "$id" '.method')"
    [[ "$method" == apt || "$method" == uv_python ]] && continue
    version="$(tool_field "$id" '.version')"
    required="$(tool_field "$id" '.required')"
    vcmd="$(uw_tmpl "$(tool_field "$id" '.verify.cmd')" "$version")"
    vre="$(tool_field "$id" '.verify.regex')"
    [[ -z "$vcmd" ]] && continue

    have="$(uw_probe_version "$vcmd" "$vre" || true)"

    if [[ -z "$have" ]]; then
      if [[ "$required" == true ]]; then
        row FAIL 工具 "$id" "$version" "缺失" "./scripts/20-binaries.sh --only $id"
      else
        row WARN 工具 "$id" "$version" "缺失（可选）" "./scripts/20-binaries.sh --only $id"
      fi
    elif [[ "$have" == "$version" ]]; then
      row OK 工具 "$id" "$version" "$have" ""
    else
      row WARN 工具 "$id" "$version" "$have（版本漂移）" "./scripts/20-binaries.sh --only $id --force"
    fi
  done
}

# ════════════════════════════════════════════════════════════════
#  C. dotfile 落地
# ════════════════════════════════════════════════════════════════
check_dotfiles() {
  local src rel target want
  # link 模式：readlink -f 必须等于仓库里的文件（能抓到「软链被换成了副本」）
  while IFS= read -r -d '' src; do
    rel="${src#"$UW_ROOT"/}"
    [[ "$rel" == *.example ]] && continue
    target="$HOME/${rel#home/}"
    want="$(readlink -f "$src")"
    if [[ ! -e "$target" ]]; then
      row FAIL 配置 "${target/#$HOME/\~}" "软链到仓库" "不存在" "./scripts/50-dotfiles.sh"
    elif [[ ! -L "$target" ]]; then
      row WARN 配置 "${target/#$HOME/\~}" "软链到仓库" "是普通文件（本地改动？）" "diff 一下，想恢复就 ./scripts/50-dotfiles.sh"
    elif [[ "$(readlink -f "$target")" != "$want" ]]; then
      row WARN 配置 "${target/#$HOME/\~}" "→ $rel" "指向别处" "./scripts/50-dotfiles.sh"
    else
      row OK 配置 "${target/#$HOME/\~}" "软链到仓库" "OK" ""
    fi
  done < <(find "$UW_ROOT/home" -type f -print0 2>/dev/null)

  # generate 模式：~/.gitconfig 必须含两条 include
  if [[ -L "$HOME/.gitconfig" ]]; then
    row FAIL 配置 "~/.gitconfig" "生成的普通文件" "是软链（危险）" "软链会让 git config --global 写进仓库工作树；跑 ./scripts/50-dotfiles.sh"
  elif [[ -f "$HOME/.gitconfig" ]] \
       && command grep -qF "$UW_ROOT/git/gitconfig" "$HOME/.gitconfig" \
       && command grep -qF ".gitconfig.local" "$HOME/.gitconfig"; then
    row OK 配置 "~/.gitconfig" "两条 include" "OK" ""
  else
    row WARN 配置 "~/.gitconfig" "两条 include" "不匹配" "./scripts/50-dotfiles.sh"
  fi

  # git 身份必须在仓库外
  local gname
  gname="$(git config --global user.name 2>/dev/null || true)"
  if [[ -z "$gname" || "$gname" == "YOUR NAME" ]]; then
    row WARN git身份 "user.name" "已填写" "未填写" "编辑 ~/.gitconfig.local 或 git config --global user.name '…'"
  else
    row OK git身份 "user.name" "已填写" "$gname" ""
  fi
}

# ════════════════════════════════════════════════════════════════
#  D. zsh 插件
# ════════════════════════════════════════════════════════════════
check_plugins() {
  need_jq
  local dest id sha dir cur
  dest="$(uw_tmpl "$(jq -r '.dest' "$UW_PLUGINS_JSON")")"
  while IFS= read -r id; do
    sha="$(jq -r --arg i "$id" '.plugins[]|select(.id==$i)|.sha' "$UW_PLUGINS_JSON")"
    dir="$dest/$id"
    if [[ ! -d "$dir/.git" ]]; then
      row FAIL 插件 "$id" "${sha:0:8}" "缺失" "./scripts/40-zsh.sh"
    else
      cur="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo '?')"
      if [[ "$cur" == "$sha" ]]; then
        row OK 插件 "$id" "${sha:0:8}" "${cur:0:8}" ""
      else
        row WARN 插件 "$id" "${sha:0:8}" "${cur:0:8}（漂移）" "./scripts/40-zsh.sh --force"
      fi
    fi
  done < <(jq -r '.plugins[].id' "$UW_PLUGINS_JSON")
}

# ════════════════════════════════════════════════════════════════
#  E. zsh 端到端 —— 单条最强信号
# ════════════════════════════════════════════════════════════════
check_zsh_runtime() {
  local zsh_bin out errout tmpe
  zsh_bin="$(uw_which zsh)"
  if [[ -z "$zsh_bin" ]]; then
    row FAIL zsh "zsh 二进制" "已安装" "缺失" "sudo apt install -y zsh"
    return
  fi

  tmpe="$(mktemp)"
  out="$("$zsh_bin" -i -c 'echo __VERIFY_OK__' 2>"$tmpe" || true)"
  errout="$(cat "$tmpe")"; rm -f "$tmpe"

  if [[ "$out" != *__VERIFY_OK__* ]]; then
    row FAIL zsh "交互式启动" "打印 token" "失败" "zsh -i -c 'echo hi' 自己看报错"
  elif [[ -n "$errout" ]]; then
    row WARN zsh "交互式启动（stderr）" "无输出" "$(printf '%s' "$errout" | head -1 | cut -c1-60)" "插件加载/compinit 有告警"
  else
    row OK zsh "交互式启动" "打印 token，stderr 为空" "OK" ""
  fi

  # PATH 卫生：GAP-FIX #4 的回归测试
  local n
  n="$("$zsh_bin" -i -c 'print -r -- $PATH' 2>/dev/null | tr ':' '\n' | command grep -cx "$HOME/.local/bin" || true)"
  if   [[ "$n" == 1 ]]; then row OK   PATH "~/.local/bin 出现次数" 1 "$n" ""
  elif [[ "$n" == 0 ]]; then row FAIL PATH "~/.local/bin 出现次数" 1 "$n" "~/.local/bin 不在 PATH 上"
  else row WARN PATH "~/.local/bin 出现次数" 1 "$n" "typeset -U path 没生效？"
  fi
}

# ════════════════════════════════════════════════════════════════
#  F. 三处 GAP-FIX 的回归测试
# ════════════════════════════════════════════════════════════════
check_gaps() {
  local zsh_bin ed edbin
  zsh_bin="$(uw_which zsh)"

  # GAP-1: EDITOR 必须解析到真实存在的二进制
  if [[ -n "$zsh_bin" ]]; then
    ed="$("$zsh_bin" -i -c 'print -r -- $EDITOR' 2>/dev/null | tail -1)"
    edbin="$(uw_which "${ed:-}" 2>/dev/null || true)"
    if [[ -z "$ed" ]]; then
      row WARN GAP-1 "EDITOR" "已设置" "为空" "检查 .zshrc 的 EDITOR 探测段"
    elif [[ -z "$edbin" ]]; then
      row FAIL GAP-1 "EDITOR=$ed" "指向已安装的二进制" "$ed 没装" "./scripts/20-binaries.sh --only neovim"
    else
      row OK GAP-1 "EDITOR=$ed" "指向已安装的二进制" "$edbin" ""
    fi
  fi

  # GAP-2: 装了 rg，alias grep=rg 才真正生效
  if [[ -n "$(uw_which rg)" ]]; then
    row OK GAP-2 "ripgrep" "已安装" "$(uw_which rg)" ""
  else
    row FAIL GAP-2 "ripgrep" "已安装" "缺失" ".zshrc 有 alias grep=rg，不装的话这条别名是死的"
  fi

  # GAP-3: tmux 配置存在且语法正确
  if [[ ! -e "$HOME/.tmux.conf" ]]; then
    row WARN GAP-3 "~/.tmux.conf" "存在" "不存在" "./scripts/50-dotfiles.sh"
  elif command -v tmux >/dev/null 2>&1; then
    if tmux -f "$HOME/.tmux.conf" start-server \; kill-server >/dev/null 2>&1; then
      row OK GAP-3 "~/.tmux.conf" "语法正确" "OK" ""
    else
      row WARN GAP-3 "~/.tmux.conf" "语法正确" "有 tmux 不认的指令" "tmux $(tmux -V 2>/dev/null) 版本差异？"
    fi
  fi
}

# ════════════════════════════════════════════════════════════════
#  G. 字体 / 登录 shell / GUI
# ════════════════════════════════════════════════════════════════
check_fonts() {
  if ! command -v fc-list >/dev/null 2>&1; then
    row WARN 字体 fontconfig "已安装" "缺 fc-list" "sudo apt install -y fontconfig"
    return
  fi
  # 只查 ghostty config 与 fontconfig 规则真正引用的两款
  local fam
  for fam in "IosevkaTermSlab Nerd Font Mono" "LXGW WenKai Mono"; do
    if font_available "$fam"; then
      row OK 字体 "$fam" 可解析 OK ""
    else
      row WARN 字体 "$fam" 可解析 "回落到别的字体" "./scripts/60-fonts.sh（缺了终端里会看到豆腐块）"
    fi
  done
}

check_shell() {
  local cur
  cur="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
  if [[ "$cur" == *zsh ]]; then
    row OK 登录shell "$USER" zsh "$cur" ""
  else
    row WARN 登录shell "$USER" zsh "$cur" "chsh -s $(uw_which zsh) —— 改完必须完整注销重登"
  fi
}

check_gui() {
  is_headless && return 0
  need_jq
  local id vcmd vre have
  while IFS= read -r id; do
    vcmd="$(tool_field "$id" '.verify.cmd')"
    vre="$(tool_field "$id" '.verify.regex')"
    have="$(uw_probe_version "$vcmd" "$vre" || true)"
    if [[ -n "$have" ]]; then
      row OK GUI "$id" 已安装 "$have" ""
    else
      row WARN GUI "$id" 已安装 缺失 "./scripts/70-desktop.sh"
    fi
  done < <(jq -r '.tools[]|select(.group=="gui" and (.method=="snap" or .method=="vendor_deb"))|.id' "$UW_TOOLS_JSON")
}

# ════════════════════════════════════════════════════════════════
#  跑
# ════════════════════════════════════════════════════════════════
check_hygiene
if [[ "$HYGIENE_ONLY" != 1 ]]; then
  check_tools
  check_dotfiles
  check_plugins
  check_zsh_runtime
  check_gaps
  check_fonts
  check_shell
  check_gui
fi

# ── 输出 ────────────────────────────────────────────────────────
if [[ "$JSON" == 1 ]]; then
  { printf '{"summary":{"ok":%d,"warn":%d,"fail":%d},"rows":[' "$N_OK" "$N_WARN" "$N_FAIL"
    first=1
    for r in "${ROWS[@]}"; do
      IFS=$'\t' read -r st cat item want got remedy <<< "$r"
      [[ $first == 1 ]] || printf ','
      first=0
      printf '{"status":"%s","category":%s,"item":%s,"expected":%s,"actual":%s,"remedy":%s}' \
        "$st" \
        "$(jq -Rn --arg v "$cat" '$v')" "$(jq -Rn --arg v "$item" '$v')" \
        "$(jq -Rn --arg v "$want" '$v')" "$(jq -Rn --arg v "$got" '$v')" \
        "$(jq -Rn --arg v "$remedy" '$v')"
    done
    printf ']}\n'; }
else
  section "verify —— profile=$PROFILE"
  printf '  %-6s %-10s %-34s %-22s %s\n' STATUS 类别 项目 期望 实际
  hr
  for r in "${ROWS[@]}"; do
    IFS=$'\t' read -r st cat item want got remedy <<< "$r"
    [[ "$BRIEF" == 1 && "$st" == OK ]] && continue
    case "$st" in
      OK)   c="$C_GRN" ;;
      WARN) c="$C_YEL" ;;
      FAIL) c="$C_RED" ;;
      *)    c="" ;;
    esac
    printf '  %b%-6s%b %-10s %-34s %-22s %s\n' "$c" "$st" "$C_RESET" "$cat" "$item" "$want" "$got"
    [[ -n "$remedy" && "$st" != OK ]] && printf '         %s↳ %s%s\n' "$C_DIM" "$remedy" "$C_RESET"
  done
  hr
  printf '  %s%d ok%s · %s%d warn%s · %s%d fail%s\n' \
    "$C_GRN" "$N_OK" "$C_RESET" "$C_YEL" "$N_WARN" "$C_RESET" "$C_RED" "$N_FAIL" "$C_RESET"
fi

[[ "$N_FAIL" -gt 0 ]] && exit 3
[[ "$N_WARN" -gt 0 ]] && exit 2
exit 0
