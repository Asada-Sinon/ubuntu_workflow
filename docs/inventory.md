# 源机器盘点

固化于 2026-08-03。这是 `manifest/*.json` 的人类可读版本 ——
数据以 manifest 为准，本文档解释「为什么是这些」。

---

## 机器

| | |
|---|---|
| OS | Ubuntu 22.04.5 LTS (jammy) |
| 内核 | 6.8.0-136-generic (HWE) |
| 架构 | x86_64 |
| 会话 | Wayland 桌面（非 headless、非 WSL、非容器） |
| Locale | `zh_CN.UTF-8` |
| 登录 shell | `/usr/bin/zsh`（zsh 5.8.1） |

---

## Shell 层

**`~/.zshrc`，12 KB，手写，无框架。** 组成：

| 段落 | 内容 |
|---|---|
| PATH | `typeset -U path PATH` 去重 + `~/.local/bin` + `~/.local/opt/node20/bin` |
| 环境 | `EDITOR`（nvim→vim→vi 探测）、`LANG`、`PAGER=less`、`LESS="-R --mouse"`、`MANPAGER` 走 bat |
| 历史 | 10 万行，`EXTENDED_HISTORY` `INC_APPEND_HISTORY` `SHARE_HISTORY` `HIST_IGNORE_ALL_DUPS` `HIST_IGNORE_SPACE` `HIST_VERIFY` |
| 目录 | `AUTO_CD` `AUTO_PUSHD` `PUSHD_IGNORE_DUPS`，`DIRSTACKSIZE=20` |
| 补全 | 自定义 compinit，缓存在 `~/.cache/zsh/zcompdump`，24 小时才重建一次；大小写不敏感匹配；`menu no`（交给 fzf-tab） |
| 键位 | emacs 风格 + `Ctrl-←/→` 词移动、Home/End/Delete、`^F` 接受建议、↑↓ 按前缀搜历史、menuselect 里 hjkl |
| 别名 | 约 25 个，全部由 `command -v` 守卫 |
| 函数 | `mkcd` / `extract` / `fkill` |
| 提示符 | `eval "$(starship init zsh)"`，放最后 |
| 尾部 | source `~/.zshrc.local`（机器私有，不进版本库），再 source uv 的 PATH 垫片 |

**插件**（手动 clone 到 `~/.local/share/zsh/plugins`，在 `.zshrc` 里按序 source）：

| 插件 | 加载顺序要求 |
|---|---|
| zsh-completions | 只加进 `fpath`，必须在 compinit **之前** |
| fzf-tab | compinit **之后**、语法高亮 **之前** |
| zsh-autosuggestions | 灰字提示，高亮色 `#6c7086`（Catppuccin overlay0） |
| zsh-you-should-use | 提醒「这条命令有别名」，`YSU_HARDCORE=0` 只提醒不阻止 |
| fast-syntax-highlighting | **必须最后**，否则会盖掉别的插件的 ZLE widget |

commit SHA 全部钉死在 `manifest/zsh-plugins.json`。

---

## 工具

**全部是 GitHub releases 的单文件静态二进制，扔进 `~/.local/bin`。**
不走 apt 的原因：jammy 的包太旧（`gh` 是 2022 年的 2.4.0）。
优先选 musl 静态版，免疫 jammy 的 glibc 2.35。

| 工具 | 版本 | 干什么 |
|---|---|---|
| fzf | 0.74.2 | 模糊查找。Ctrl-T / Ctrl-R / Alt-C，fzf-tab 也依赖它 |
| fd | 10.4.2 | `alias find=fd`，也是 `FZF_DEFAULT_COMMAND` |
| **ripgrep** | 15.2.0 | **补装**（GAP-FIX #2） |
| bat | 0.26.1 | `alias cat=bat`，MANPAGER 和 fzf 预览也用 |
| eza | 0.23.5 | ls 家族 8 个别名全指向它 |
| zoxide | 0.10.0 | `z` / `zi` 智能跳目录 |
| btop | 1.4.7 | `alias top=btop` |
| delta | 0.19.2 | git 分页器，并排 diff |
| starship | 1.26.0 | 提示符 |
| atuin | 18.18.1 | Ctrl-R 历史数据库，默认纯本地 |
| fastfetch | 2.66.0 | 系统信息展示 |
| gh | 2.97.0 | GitHub CLI，同时是 git 的 credential helper |
| **neovim** | 0.12.4 | **补装**（GAP-FIX #1） |
| uv | 0.12.1 | 唯一的 Python 管理器 |
| jq | 1.8.2 | 本仓库自己的 manifest 解析器 |
| node | 20.20.2 | 装在 `~/.local/opt/node20`（jammy apt 只有 node 12） |

**apt 装的**：zsh git curl wget jq tmux unzip zip xz-utils ca-certificates
gnupg fontconfig build-essential cmake less man-db bzip2 zstd
（+ desktop profile 下的 fonts-noto-cjk / fonts-noto-color-emoji）

**Python**：没有 pip / pipx / conda / mamba / pyenv。系统 `python3` 是 3.10.12，
实际开发用 uv 托管的 CPython 3.12。刻意如此。

---

## 配置文件

| 文件 | 内容 |
|---|---|
| `~/.config/starship.toml` | 253 行，Catppuccin Mocha powerline，含 mocha/macchiato/latte 三套调色板 |
| `~/.config/ghostty/config` | 字体链、主题、透明度 0.94 + 模糊 20、10 万行回滚、选中即复制、分屏/标签快捷键 |
| `~/.config/bat/{config,themes/}` | 4 个 Catppuccin tmTheme |
| `~/.config/btop/{btop.conf,themes/}` | 3 个 Catppuccin theme |
| `~/.config/atuin/config.toml` | 纯本地、fuzzy、compact；`history_filter` 拦 pass/gopass/AWS_SECRET_ACCESS_KEY/`export *TOKEN=` |
| `~/.config/delta/catppuccin.gitconfig` | 123 行，delta 的四套 Catppuccin 配色 |
| `~/.config/fastfetch/config.jsonc` | 模块布局 |
| `~/.config/fontconfig/conf.d/99-cjk-serif-mono.conf` | 给三款 Nerd Font 配中文 fallback。刻意不动通用 `monospace`（会把其它程序的拉丁字形也换成楷体） |
| `~/.tmux.conf` | **新写**（GAP-FIX #3） |
| `~/.gitconfig` | 剥离身份后成为 `git/gitconfig` |

---

## 字体

源机器上 NerdFonts 1.4 GB + CJK 238 MB，所以**不进版本库**，由脚本下载。

| 字体 | 集合 | 为什么 |
|---|---|---|
| IosevkaTermSlab NF | minimal | ★ ghostty 的主字体，衬线等宽 |
| LXGW WenKai Mono | minimal | ★ 中文 fallback，霞鹜文楷。拉丁字体不含汉字，必然回退到它 |
| JetBrainsMono NF | full | 经典无衬线，ghostty 注释里的备选 |
| Meslo NF | full | p10k 推荐款（本配置不用 p10k），备选 |
| Monaspace NF | full | 其中 Xenon 是 slab serif，被 fontconfig 第二条规则引用 |
| FiraCode NF | full | 连字，备选 |
| CodeNewRoman NF | full | Times New Roman 血统，被 fontconfig 第三条规则引用 |

---

## GUI

| | |
|---|---|
| Ghostty | v1.3.1，snap classic，打包者 `ken-vandine`（**非官方**） |
| Termius | 9.42.2，官方 deb 源，装在 `/opt/Termius`（Electron） |
| GNOME Terminal | dconf profile，Catppuccin Mocha 色板，Iosevka 13，130×40 |

---

## 刻意排除在外的

| | 为什么 |
|---|---|
| SSH 配置与密钥 | 不在本仓库范围内 |
| git 身份 | public 仓库 |
| Termius 主机数据 | 加密 IndexedDB，不可移植 |
| fcitx5 输入法 | 系统级 + 桌面会话的事，跟终端环境不是一回事 |
| Tailscale | 网络层，与终端无关 |
| VS Code / `.vscode-server` | 有自己的设置同步 |
| WindTerm | 装在 `~/apps` 的便携版，profile 看起来几乎没用过 |
| ToDesk | 远程桌面，与终端无关 |
