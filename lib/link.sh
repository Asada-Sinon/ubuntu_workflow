#!/usr/bin/env bash
# lib/link.sh —— dotfile 落地：link / copy / generate / append
#
# 默认策略是软链，好处是之后 `git status` 免费变成
# 「我最近手改过哪些配置」的 diff。
#
# 绝不静默覆盖：目标已存在且不是我们的软链时，先备份到
# ~/.config/ubuntu_workflow/backup/<时间戳>/ 并记进报告。

[[ -n "${_UW_LINK_LOADED:-}" ]] && return 0
_UW_LINK_LOADED=1

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

UW_BACKUP_DIR=""   # 本次运行的备份目录，懒创建

_uw_backup_dir() {
  if [[ -z "$UW_BACKUP_DIR" ]]; then
    UW_BACKUP_DIR="$UW_BACKUP_ROOT/$(date +%Y%m%dT%H%M%S)"
    [[ "$DRY_RUN" == 1 ]] || mkdir -p "$UW_BACKUP_DIR"
  fi
  printf '%s' "$UW_BACKUP_DIR"
}

# 把已存在的目标挪走（不删）
uw_backup_target() {
  local target="$1" bdir rel
  [[ -e "$target" || -L "$target" ]] || return 0
  bdir="$(_uw_backup_dir)"
  rel="${target#"$HOME"/}"
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  备份 %s → %s/%s%s\n' "$C_DIM" "$target" "$bdir" "$rel" "$C_RESET"
    return 0
  fi
  mkdir -p "$bdir/$(dirname "$rel")"
  mv "$target" "$bdir/$rel"
  warn "已备份原有 $target → $bdir/$rel"
  report 50 "backup:$rel" ok "$bdir/$rel"
}

# ── link ────────────────────────────────────────────────────────
uw_link() { # uw_link <src-abs> <target-abs>
  local src="$1" target="$2"

  if [[ -L "$target" ]]; then
    local cur; cur="$(readlink -f "$target" 2>/dev/null || true)"
    if [[ "$cur" == "$(readlink -f "$src")" ]]; then
      skip "已链接 ${target/#$HOME/\~}"
      return 10
    fi
  fi

  [[ -e "$target" || -L "$target" ]] && uw_backup_target "$target"

  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  链接 %s → %s%s\n' "$C_DIM" "${target/#$HOME/\~}" "$src" "$C_RESET"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  ln -sfn "$src" "$target"
  ok "链接 ${target/#$HOME/\~}"
}

# ── copy ────────────────────────────────────────────────────────
uw_copy() {
  local src="$1" target="$2"
  if [[ -f "$target" ]] && cmp -s "$src" "$target"; then
    skip "已是最新 ${target/#$HOME/\~}"
    return 10
  fi
  [[ -e "$target" || -L "$target" ]] && uw_backup_target "$target"
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  复制 %s → %s%s\n' "$C_DIM" "$src" "${target/#$HOME/\~}" "$C_RESET"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  cp "$src" "$target"
  ok "复制 ${target/#$HOME/\~}"
}

# ── seed：只在目标不存在时用示例初始化，绝不覆盖 ────────────────
uw_seed() {
  local src="$1" target="$2"
  if [[ -e "$target" ]]; then
    skip "已存在，保留不动 ${target/#$HOME/\~}"
    return 10
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  初始化 %s（来自 %s）%s\n' "$C_DIM" "${target/#$HOME/\~}" "$(basename "$src")" "$C_RESET"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  cp "$src" "$target"
  ok "初始化 ${target/#$HOME/\~}（从示例）"
}

# ── append：围栏块，可重复替换 ──────────────────────────────────
UW_MARK_BEGIN='# >>> ubuntu_workflow >>>'
UW_MARK_END='# <<< ubuntu_workflow <<<'

uw_append_block() { # uw_append_block <file> <内容...>
  local file="$1"; shift
  local body="$*"
  local new
  new="$(printf '%s\n%s\n%s' "$UW_MARK_BEGIN" "$body" "$UW_MARK_END")"

  if [[ -f "$file" ]] && grep -qF "$UW_MARK_BEGIN" "$file"; then
    local cur
    cur="$(sed -n "/^$(printf '%s' "$UW_MARK_BEGIN" | sed 's/[][\.*^$/]/\\&/g')$/,/^$(printf '%s' "$UW_MARK_END" | sed 's/[][\.*^$/]/\\&/g')$/p" "$file")"
    if [[ "$cur" == "$new" ]]; then
      skip "围栏块已是最新 ${file/#$HOME/\~}"
      return 10
    fi
    if [[ "$DRY_RUN" == 1 ]]; then
      printf '%s  DRY  更新 %s 里的围栏块%s\n' "$C_DIM" "${file/#$HOME/\~}" "$C_RESET"
      return 0
    fi
    # 删掉旧块再追加新块
    local tmp; tmp="$(mktemp)"
    sed "/^$(printf '%s' "$UW_MARK_BEGIN" | sed 's/[][\.*^$/]/\\&/g')$/,/^$(printf '%s' "$UW_MARK_END" | sed 's/[][\.*^$/]/\\&/g')$/d" "$file" > "$tmp"
    printf '%s\n' "$new" >> "$tmp"
    mv "$tmp" "$file"
    ok "更新围栏块 ${file/#$HOME/\~}"
    return 0
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  往 %s 追加围栏块%s\n' "$C_DIM" "${file/#$HOME/\~}" "$C_RESET"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  { [[ -f "$file" ]] && printf '\n'; printf '%s\n' "$new"; } >> "$file"
  ok "追加围栏块 ${file/#$HOME/\~}"
}

# ── generate：~/.gitconfig 专用 ─────────────────────────────────
# ★ 全设计里最关键的一处。
#   若直接软链 ~/.gitconfig → 仓库文件，那么一条
#     git config --global user.email me@example.com
#   就会把真实邮箱写进仓库工作树 —— 而这是 public 仓库，没有撤销余地。
#   改成生成一个只含两条 [include] 的真实文件，所有 --global 写入
#   都落到仓库外的 ~/.gitconfig，永远不会被 git add 到。
uw_generate_gitconfig() {
  local repo_gitconfig="$1" target="$HOME/.gitconfig"
  local content
  content="$(cat <<EOF
# 本文件由 ubuntu_workflow 的 50-dotfiles.sh 生成 —— 可以随便改。
#
# 工具链配置（delta 分页器、配色、merge 风格）来自仓库，跟着 git pull 更新。
# 你的身份（user.name / user.email）写在 ~/.gitconfig.local，那个文件
# 不进版本库。\`git config --global\` 的写入会落在本文件里，同样不进版本库。
#
# 刻意不把 ~/.gitconfig 软链到仓库：那样 \`git config --global user.email\`
# 会直接改动仓库工作树，而仓库是 public 的。

[include]
	path = $repo_gitconfig

[include]
	path = ~/.gitconfig.local
EOF
)"

  if [[ -f "$target" ]] && [[ "$(cat "$target")" == "$content" ]]; then
    skip "~/.gitconfig 已是最新"
    return 10
  fi

  [[ -e "$target" ]] && uw_backup_target "$target"

  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s  DRY  生成 ~/.gitconfig（两条 include）%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi
  printf '%s\n' "$content" > "$target"
  ok "生成 ~/.gitconfig"
}
