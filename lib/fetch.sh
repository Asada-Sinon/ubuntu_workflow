#!/usr/bin/env bash
# lib/fetch.sh —— 下载 + 解包 + 原子安装
#
# 全仓库杠杆最高的一段：16 个工具走同一条路径，所以这里的正确性
# 基本决定了整个仓库的可靠性。
#
# 分两层：
#   install_binary_from_url  通用（node 来自 nodejs.org，不是 GitHub 形状）
#   install_github_release   薄封装，拼出 releases/download URL 后委托给上面那个
#
# 三个必须做对的细节：
#   1. 原子安装 —— 解到 mktemp，install 到目标目录的临时名，再 mv。
#      Ctrl-C 打断不会在 PATH 上留下截断的二进制。
#   2. 装完重验版本 —— 抓「上游改了 asset 名、glob 抓错文件却装成功」这种
#      静默失败。nvim 0.11 就干过（nvim-linux64 → nvim-linux-x86_64）。
#   3. 下载缓存 —— 重试和 --force 重跑免费；把 cache 目录拷到另一台机器
#      就能离线安装。

[[ -n "${_UW_FETCH_LOADED:-}" ]] && return 0
_UW_FETCH_LOADED=1

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ── curl 包装 ───────────────────────────────────────────────────
_uw_curl() {
  curl --fail --location --silent --show-error \
       --proto '=https' --tlsv1.2 \
       --retry 3 --retry-delay 2 --retry-connrefused \
       --connect-timeout 15 --max-time 900 \
       "$@"
}

# HEAD 检查 —— --dry-run 时用，顺带就是整个 manifest 的链接腐烂检查器
uw_url_alive() {
  local url="$1" code
  code="$(curl -o /dev/null -sIL -w '%{http_code}' --proto '=https' \
          --connect-timeout 15 --max-time 60 "$url" 2>/dev/null)"
  [[ "$code" == 200 ]]
}

# ── 下载到缓存 ──────────────────────────────────────────────────
# 缓存文件名 = url 的 sha256 前 12 位 + 原始 basename，避免不同版本同名冲突
_uw_download() {
  local url="$1" out
  local key base
  key="$(printf '%s' "$url" | sha256sum | cut -c1-12)"
  base="$(basename "${url%%\?*}")"
  out="$UW_DOWNLOADS/${key}-${base}"

  if [[ -s "$out" && "$FORCE" != 1 ]]; then
    debug "缓存命中：$out"
    printf '%s' "$out"; return 0
  fi
  mkdir -p "$UW_DOWNLOADS"
  debug "下载：$url"
  if ! _uw_curl -o "$out.part" "$url"; then
    rm -f "$out.part"
    return 1
  fi
  mv "$out.part" "$out"
  printf '%s' "$out"
}

# ── 校验 ────────────────────────────────────────────────────────
_uw_verify_sha256() {
  local file="$1" want="$2" got
  got="$(sha256sum "$file" | cut -d' ' -f1)"
  if [[ "$got" != "$want" ]]; then
    err "sha256 不匹配：$(basename "$file")"
    err "  期望 $want"
    err "  实际 $got"
    rm -f "$file"          # 删掉缓存，免得下次继续用坏文件
    return 1
  fi
  return 0
}

# ── 解包 ────────────────────────────────────────────────────────
# 按扩展名分派。--strip N 丢掉前 N 层路径。
_uw_extract() {
  local file="$1" dir="$2" strip="${3:-0}"
  mkdir -p "$dir"
  case "$file" in
    *.tar.gz|*.tgz)    tar -xzf  "$file" -C "$dir" ${strip:+--strip-components="$strip"} ;;
    *.tar.xz|*.txz)    tar -xJf  "$file" -C "$dir" ${strip:+--strip-components="$strip"} ;;
    *.tar.bz2|*.tbz|*.tbz2) tar -xjf "$file" -C "$dir" ${strip:+--strip-components="$strip"} ;;
    *.tar.zst)         tar --zstd -xf "$file" -C "$dir" ${strip:+--strip-components="$strip"} ;;
    *.tar)             tar -xf   "$file" -C "$dir" ${strip:+--strip-components="$strip"} ;;
    *.zip)             unzip -q -o "$file" -d "$dir" ;;
    *.gz)              gunzip -c "$file" > "$dir/$(basename "${file%.gz}")" ;;
    *)                 cp "$file" "$dir/" ;;   # 裸二进制
  esac
}

# ── 原子安装单个文件 ────────────────────────────────────────────
_uw_install_file() {
  local src="$1" dest="$2" mode="${3:-0755}"
  local dir tmp
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.uw-XXXXXX")"
  cp "$src" "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$dest"      # mv 在同一文件系统上是原子的
}

# 在解包目录里按 glob 找唯一一个文件
_uw_glob_one() {
  local root="$1" pat="$2" hits
  # 先当相对 glob 试，再当 basename 试
  mapfile -t hits < <(cd "$root" && compgen -G "$pat" 2>/dev/null | head -20)
  if [[ ${#hits[@]} -eq 0 ]]; then
    mapfile -t hits < <(find "$root" -type f -name "$(basename "$pat")" 2>/dev/null | head -20)
    [[ ${#hits[@]} -gt 0 ]] && { printf '%s' "${hits[0]}"; return 0; }
    return 1
  fi
  printf '%s' "$root/${hits[0]}"
}

# ════════════════════════════════════════════════════════════════
#  install_binary_from_url —— 通用安装器
#
#  返回值：0 = 已安装   10 = 跳过（版本已匹配）   其它 = 失败
# ════════════════════════════════════════════════════════════════
install_binary_from_url() {
  local name="" url="" version="" pick="" as="" strip="" dest="" mode="0755"
  local sha256="" sha256_url="" check="" check_regex="" force_this=0
  local -a extras=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)        name="$2";        shift 2 ;;
      --url)         url="$2";         shift 2 ;;
      --version)     version="$2";     shift 2 ;;
      --pick)        pick="$2";        shift 2 ;;
      --as)          as="$2";          shift 2 ;;
      --strip)       strip="$2";       shift 2 ;;
      --dest)        dest="$2";        shift 2 ;;
      --mode)        mode="$2";        shift 2 ;;
      --extra)       extras+=("$2");   shift 2 ;;
      --sha256)      sha256="$2";      shift 2 ;;
      --sha256-url)  sha256_url="$2";  shift 2 ;;
      --check)       check="$2";       shift 2 ;;
      --check-regex) check_regex="$2"; shift 2 ;;
      --force)       force_this=1;     shift   ;;
      *) err "install_binary_from_url: 未知参数 $1"; return 2 ;;
    esac
  done

  [[ -n "$name" && -n "$url" ]] || { err "install_binary_from_url: 缺 --name/--url"; return 2; }
  as="${as:-$name}"
  dest="${dest:-$BIN_DIR}"

  # ── 1. 幂等：版本已匹配就跳过 ──────────────────────────────
  if [[ -n "$check" && -n "$check_regex" && "$force_this" != 1 && "$FORCE" != 1 ]]; then
    local have
    have="$(uw_probe_version "$check" "$check_regex" || true)"
    if [[ -n "$have" && "$have" == "$version" ]]; then
      skip "$name $version 已安装"
      return 10
    fi
    [[ -n "$have" ]] && info "$name：本机 $have → 目标 $version"
  fi

  # ── dry-run：只做 HEAD，顺带查链接腐烂 ─────────────────────
  if [[ "$DRY_RUN" == 1 ]]; then
    if uw_url_alive "$url"; then
      printf '%s  DRY  %-12s %-8s %s%s\n' "$C_DIM" "$name" "$version" "$url" "$C_RESET"
      return 0
    else
      err "$name：URL 不可达（链接腐烂？）$url"
      return 1
    fi
  fi

  # ── 2. 下载 ────────────────────────────────────────────────
  local archive
  archive="$(_uw_download "$url")" || { err "$name：下载失败 $url"; return 1; }

  # ── 3. 校验 ────────────────────────────────────────────────
  if [[ -z "$sha256" && -n "$sha256_url" ]]; then
    local sums
    if sums="$(_uw_curl "$sha256_url" 2>/dev/null)"; then
      sha256="$(printf '%s\n' "$sums" | grep -F "$(basename "${url%%\?*}")" | awk '{print $1}' | head -1)"
    fi
  fi
  if [[ -n "$sha256" ]]; then
    _uw_verify_sha256 "$archive" "$sha256" || { err "$name：校验和不匹配"; return 1; }
    debug "$name：sha256 OK"
  fi

  # ── 4-6. 解包 → 挑文件 → 原子安装 ──────────────────────────
  local tmpd; tmpd="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpd'" RETURN

  if [[ -z "$pick" ]]; then
    # asset 本身就是二进制（如 jq-linux-amd64）
    _uw_install_file "$archive" "$dest/$as" "$mode"
  else
    _uw_extract "$archive" "$tmpd" "$strip" || { err "$name：解包失败"; return 1; }
    local src
    src="$(_uw_glob_one "$tmpd" "$pick")" || { err "$name：归档里找不到 '$pick'（上游改 asset 结构了？）"; return 1; }
    _uw_install_file "$src" "$dest/$as" "$mode"
  fi

  # ── 6b. --extra：补全脚本、man page 等 ─────────────────────
  local pair epat edst esrc
  for pair in "${extras[@]}"; do
    epat="${pair%%:*}"; edst="${pair#*:}"
    edst="$(uw_tmpl "$edst" "$version")"
    if esrc="$(_uw_glob_one "$tmpd" "$epat" 2>/dev/null)"; then
      _uw_install_file "$esrc" "$edst" 0644
      debug "$name：extra $epat → $edst"
    else
      debug "$name：extra 没找到（不致命）：$epat"
    fi
  done

  # ── 7. 装完重验 ────────────────────────────────────────────
  # 抓「装成功了但装错了东西」——本项目预期的头号静默失败。
  if [[ -n "$check" && -n "$check_regex" ]]; then
    local now
    now="$(uw_probe_version "$check" "$check_regex" || true)"
    if [[ -z "$now" ]]; then
      err "$name：装完却跑不起来（$check）"
      return 1
    fi
    if [[ -n "$version" && "$now" != "$version" ]]; then
      err "$name：装完版本对不上 —— 期望 $version，实际 $now（asset 抓错了？）"
      return 1
    fi
  fi

  ok "$name $version → $dest/$as"
  return 0
}

# ════════════════════════════════════════════════════════════════
#  install_github_release —— 薄封装
# ════════════════════════════════════════════════════════════════
install_github_release() {
  local repo="" tag="" asset="" version=""
  local -a pass=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)    repo="$2";             shift 2 ;;
      --tag)     tag="$2";              shift 2 ;;
      --asset)   asset="$2";            shift 2 ;;
      --version) version="$2"; pass+=(--version "$2"); shift 2 ;;
      *)         pass+=("$1");          shift   ;;
    esac
  done
  [[ -n "$repo" && -n "$tag" && -n "$asset" ]] || { err "install_github_release: 缺 --repo/--tag/--asset"; return 2; }

  local t a url
  t="$(uw_tmpl "$tag" "$version")"
  a="$(uw_tmpl "$asset" "$version")"
  url="https://github.com/$repo/releases/download/$t/$a"

  install_binary_from_url --url "$url" "${pass[@]}"
}

# ════════════════════════════════════════════════════════════════
#  install_archive_to_dir —— 整个目录树的安装（node20 / neovim）
# ════════════════════════════════════════════════════════════════
install_archive_to_dir() {
  local name="" url="" version="" dest="" strip="1" check="" check_regex=""
  local -a link_bins=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)        name="$2";        shift 2 ;;
      --url)         url="$2";         shift 2 ;;
      --version)     version="$2";     shift 2 ;;
      --dest)        dest="$2";        shift 2 ;;
      --strip)       strip="$2";       shift 2 ;;
      --link-bin)    link_bins+=("$2");shift 2 ;;
      --check)       check="$2";       shift 2 ;;
      --check-regex) check_regex="$2"; shift 2 ;;
      *) err "install_archive_to_dir: 未知参数 $1"; return 2 ;;
    esac
  done

  if [[ -n "$check" && -n "$check_regex" && "$FORCE" != 1 ]]; then
    local have; have="$(uw_probe_version "$check" "$check_regex" || true)"
    if [[ -n "$have" && "$have" == "$version" ]]; then
      skip "$name $version 已安装"
      return 10
    fi
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    if uw_url_alive "$url"; then
      printf '%s  DRY  %-12s %-8s %s%s\n' "$C_DIM" "$name" "$version" "$url" "$C_RESET"
      return 0
    else
      err "$name：URL 不可达（链接腐烂？）$url"; return 1
    fi
  fi

  local archive; archive="$(_uw_download "$url")" || { err "$name：下载失败 $url"; return 1; }

  local tmpd; tmpd="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpd'" RETURN
  _uw_extract "$archive" "$tmpd" "$strip" || { err "$name：解包失败"; return 1; }

  # 原子替换整个目录：先装到 dest.new，再 swap，最后删旧的
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest.new"
  cp -a "$tmpd" "$dest.new"
  [[ -d "$dest" ]] && mv "$dest" "$dest.old"
  mv "$dest.new" "$dest"
  rm -rf "$dest.old"

  # 把要暴露的可执行文件软链进 ~/.local/bin
  local b
  for b in "${link_bins[@]}"; do
    mkdir -p "$BIN_DIR"
    ln -sfn "$dest/$b" "$BIN_DIR/$(basename "$b")"
    debug "$name：链接 $BIN_DIR/$(basename "$b") → $dest/$b"
  done

  if [[ -n "$check" && -n "$check_regex" ]]; then
    local now; now="$(uw_probe_version "$check" "$check_regex" || true)"
    [[ -z "$now" ]] && { err "$name：装完却跑不起来（$check）"; return 1; }
    if [[ -n "$version" && "$now" != "$version" ]]; then
      err "$name：装完版本对不上 —— 期望 $version，实际 $now"
      return 1
    fi
  fi

  ok "$name $version → $dest"
  return 0
}
