#  ═══════════════════════════════════════════════════════════════
#  ~/.zshrc
#  Starship + fzf + zoxide + atuin + eza/bat/fd/delta
#  配色统一 Catppuccin Mocha
#  ═══════════════════════════════════════════════════════════════

# ── PATH（从原 .bashrc 迁移）────────────────────────────────────
# typeset -U 让 path 数组自动去重：.profile / ~/.local/bin/env / 本文件
# 会各自 prepend 一次，不去重的话 $PATH 里会出现四份 ~/.local/bin。
typeset -U path PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.local/opt/node20/bin:$PATH"

# ── 基础环境 ────────────────────────────────────────────────────
# 按 nvim → vim → vi 探测，不硬写 vim。
# （原来固定写 vim，但机器上 vim/nvim 都没装，git commit 不带 -m 会直接失败）
if [[ -z "$EDITOR" ]]; then
  for _ed in nvim vim vi; do
    if command -v "$_ed" >/dev/null 2>&1; then export EDITOR="$_ed"; break; fi
  done
  unset _ed
fi
export VISUAL="$EDITOR"
export LANG="${LANG:-zh_CN.UTF-8}"

# less / man 用 bat 上色
export PAGER="less"
export LESS="-R --mouse --wheel-lines=3"
if command -v bat >/dev/null 2>&1; then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export MANROFFOPT="-c"
fi

# ── 历史 ────────────────────────────────────────────────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY          # 记录时间戳
setopt INC_APPEND_HISTORY        # 立即写入，不等退出
setopt SHARE_HISTORY             # 多终端共享
setopt HIST_IGNORE_DUPS          # 连续重复只记一次
setopt HIST_IGNORE_ALL_DUPS      # 旧的重复项删掉
setopt HIST_IGNORE_SPACE         # 空格开头的命令不记录
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY               # 历史展开先确认再执行

# ── 目录导航 ────────────────────────────────────────────────────
setopt AUTO_CD                   # 直接输目录名即 cd
setopt AUTO_PUSHD                # cd 自动入栈
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
DIRSTACKSIZE=20

# ── 补全与交互 ──────────────────────────────────────────────────
setopt ALWAYS_TO_END
setopt COMPLETE_IN_WORD
setopt GLOB_DOTS                 # 通配符匹配隐藏文件
setopt INTERACTIVE_COMMENTS      # 交互式下允许 # 注释
setopt NO_BEEP
unsetopt FLOW_CONTROL            # 释放 Ctrl-S / Ctrl-Q

ZPLUG="$HOME/.local/share/zsh/plugins"

# 补全系统（带缓存，加速启动）
# 第二个目录放各工具自带的补全（rg / fd / delta 的 tarball 里就带，
# 由 60/20 脚本的 --extra 解出来丢这儿）
fpath=("$ZPLUG/zsh-completions/src" "$HOME/.local/share/zsh/completions" $fpath)
autoload -Uz compinit
_zcompdump="$HOME/.cache/zsh/zcompdump"
mkdir -p "$(dirname "$_zcompdump")"
# 一天只重建一次补全缓存
if [[ -n "$_zcompdump"(#qN.mh+24) ]]; then
  compinit -d "$_zcompdump"
else
  compinit -C -d "$_zcompdump"
fi

zmodload zsh/complist

# 补全样式：菜单选择、大小写不敏感、彩色、分组标题
zstyle ':completion:*' menu no                      # 交给 fzf-tab 接管
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose true
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:warnings'     format ' %F{red}没有匹配项%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.cache/zsh/zcompcache"
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' squeeze-slashes true

# ── 插件 ────────────────────────────────────────────────────────
# fzf-tab 必须在 compinit 之后、语法高亮之前
[[ -f "$ZPLUG/fzf-tab/fzf-tab.plugin.zsh" ]] && source "$ZPLUG/fzf-tab/fzf-tab.plugin.zsh"

# 自动建议（灰字提示历史命令，→ 或 Ctrl-F 接受）
if [[ -f "$ZPLUG/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$ZPLUG/zsh-autosuggestions/zsh-autosuggestions.zsh"
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'      # Catppuccin overlay0
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
fi

# 提醒你「这条命令有 alias」
if [[ -f "$ZPLUG/zsh-you-should-use/you-should-use.plugin.zsh" ]]; then
  export YSU_MESSAGE_POSITION="after"
  export YSU_HARDCORE=0
  source "$ZPLUG/zsh-you-should-use/you-should-use.plugin.zsh"
fi

# 语法高亮必须放在最后加载
[[ -f "$ZPLUG/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ]] \
  && source "$ZPLUG/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"

# ── fzf ─────────────────────────────────────────────────────────
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)   # Ctrl-T 找文件 / Ctrl-R 历史 / Alt-C 跳目录

  # Catppuccin Mocha 配色 + 圆角边框
  export FZF_DEFAULT_OPTS="
    --height=60% --layout=reverse --border=rounded --info=inline-right
    --marker='▏' --pointer='▶' --prompt='  '
    --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
    --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
    --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
    --color=selected-bg:#45475a
    --color=border:#6c7086,label:#cdd6f4"

  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi
  # 预览：文件用 bat，目录用 eza
  export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always --line-range :300 {} 2>/dev/null || eza -T --color=always --icons {} 2>/dev/null' --preview-window=right:60%:wrap"
  export FZF_ALT_C_OPTS="--preview 'eza -T --level=2 --color=always --icons {}'"
  export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window=down:3:hidden:wrap --bind '?:toggle-preview'"

  # fzf-tab 的预览
  zstyle ':fzf-tab:complete:cd:*'      fzf-preview 'eza -1 --color=always --icons $realpath'
  zstyle ':fzf-tab:complete:z:*'       fzf-preview 'eza -1 --color=always --icons $realpath'
  zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --color=always --icons $realpath'
  zstyle ':fzf-tab:complete:*:*'       fzf-preview '[[ -d $realpath ]] && eza -1 --color=always --icons $realpath || bat -n --color=always --line-range :200 $realpath 2>/dev/null'
  zstyle ':fzf-tab:*' fzf-command fzf
  zstyle ':fzf-tab:*' switch-group '<' '>'
  zstyle ':fzf-tab:*' use-fzf-default-opts yes
  zstyle ':fzf-tab:*' fzf-flags --height=60%
fi

# ── zoxide（智能 cd）────────────────────────────────────────────
# z foo 跳到最常访问的含 foo 的目录；zi 用 fzf 交互选择
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ── atuin（历史数据库 + 同步）───────────────────────────────────
# 只接管 Ctrl-R，上箭头保留 zsh 原生行为
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh --disable-up-arrow)"

# ── 别名 ────────────────────────────────────────────────────────
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons --group-directories-first'
  alias l='eza -1 --icons --group-directories-first'
  alias ll='eza -lh --icons --group-directories-first --git --time-style=long-iso'
  alias la='eza -lah --icons --group-directories-first --git --time-style=long-iso'
  alias lt='eza -T --level=2 --icons --group-directories-first'
  alias ltt='eza -T --level=4 --icons --group-directories-first'
  alias lsize='eza -lah --icons --sort=size --reverse'
  alias lnew='eza -lah --icons --sort=modified --reverse'
else
  alias ls='ls --color=auto'
  alias ll='ls -alF'
  alias la='ls -A'
fi

command -v bat  >/dev/null 2>&1 && { alias cat='bat --paging=never'; alias catp='bat -p --paging=never'; }
command -v btop >/dev/null 2>&1 && alias top='btop'
command -v fd   >/dev/null 2>&1 && alias find='fd'
# 注意：rg 与 grep 的参数不完全兼容（-r/-e/--include 等语义不同）。
# 脚本里请写 `command grep` 或直接写 rg，别依赖这个别名。
command -v rg   >/dev/null 2>&1 && alias grep='rg'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ip='ip -c'
alias path='echo $PATH | tr ":" "\n"'
alias reload='exec zsh'
alias zshrc='$EDITOR ~/.zshrc'

# git
alias g='git'
alias gs='git status -sb'
alias gd='git diff'
alias gds='git diff --staged'
alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gl='git pull'
alias glog='git log --graph --oneline --decorate --all -30'

# apt
alias aptup='sudo apt update && sudo apt upgrade'
alias apti='sudo apt install'
alias apts='apt search'

# ── 小函数 ──────────────────────────────────────────────────────
# mkcd: 建目录并进去
mkcd() { mkdir -p "$1" && cd "$1"; }

# extract: 万能解压
extract() {
  [[ -f "$1" ]] || { echo "'$1' 不是文件"; return 1; }
  case "$1" in
    *.tar.bz2|*.tbz2) tar xjf "$1"   ;;
    *.tar.gz|*.tgz)   tar xzf "$1"   ;;
    *.tar.xz)         tar xJf "$1"   ;;
    *.tar.zst)        tar --zstd -xf "$1" ;;
    *.tar)            tar xf  "$1"   ;;
    *.bz2)            bunzip2 "$1"   ;;
    *.gz)             gunzip  "$1"   ;;
    *.zip)            unzip   "$1"   ;;
    *.7z)             7z x    "$1"   ;;
    *.rar)            unrar x "$1"   ;;
    *) echo "不认识的压缩格式: $1"; return 1 ;;
  esac
}

# fkill: fzf 选进程杀掉
fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m --header='[选择要结束的进程]' | awk '{print $2}')
  [[ -n "$pid" ]] && echo "$pid" | xargs kill -${1:-9}
}

# ── 键位绑定 ────────────────────────────────────────────────────
bindkey -e                                   # emacs 风格（Ctrl-A/E/K/U 等）
bindkey '^[[1;5C' forward-word               # Ctrl-→
bindkey '^[[1;5D' backward-word              # Ctrl-←
bindkey '^[[H'    beginning-of-line          # Home
bindkey '^[[F'    end-of-line                # End
bindkey '^[[3~'   delete-char                # Delete
bindkey '^[[3;5~' kill-word                  # Ctrl-Delete
bindkey '^H'      backward-kill-word         # Ctrl-Backspace
bindkey '^F'      autosuggest-accept         # Ctrl-F 接受建议

# 上下键：按已输入前缀搜索历史
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# 补全菜单里用 hjkl 移动
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char

# ── 提示符：Starship 放最后 ─────────────────────────────────────
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"

# 本机私有配置（不纳入版本管理）
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# uv 写的 PATH 垫片。uv 自己生成时用的是 "$HOME/.local/share/../bin/env"
# 这种拼法，字符串上不等于 "$HOME/.local/bin"，所以它内部的去重守卫永远
# 不触发 —— 这里归一化路径，去重交给上面的 typeset -U path。
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
