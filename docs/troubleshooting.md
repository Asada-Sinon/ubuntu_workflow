# 排错

---

## 改了登录 shell 但没生效

**要完整注销重新登录**，不是开新终端标签页，也不是 `exec zsh`。
登录 shell 是登录会话建立的那一刻读的。

确认当前值：

```bash
getent passwd "$USER" | cut -d: -f7
```

---

## `command -v <tool>` 说装了，但其实没装

你的 shell 里有同名的**函数或别名**。两个常见来源：

- **Claude Code 之类的 agent harness** 会从
  `~/.claude/shell-snapshots/snapshot-zsh-*.sh` 注入 shell 函数。
  实测：即使 PATH 上根本没有 ripgrep 二进制，`command -v rg` 也返回成功。
- **这套配置自己的 `.zshrc`** 给 `cat` / `find` / `grep` / `top` 都加了别名。

正确的查法：

```bash
PATH=/usr/bin:/bin type -P rg     # bash builtin，只查 PATH
./verify.sh                        # 内部就是这么做的
```

---

## 某个工具下载失败 / 404

最常见的原因是**上游改了 release asset 的名字**。

```bash
./bootstrap.sh --dry-run     # 对 manifest 里每个 URL 发 HEAD，直接指出哪个死了
```

然后：

1. 去上游 releases 页面看新的 asset 名；
2. 改 `manifest/tools.json` 里对应条目的 `version` / `github.asset`；
3. `./scripts/20-binaries.sh --only <id>`

manifest 里已经记了几处不规则写法，改的时候留意：

| 工具 | 坑 |
|---|---|
| ripgrep | tag **没有** `v` 前缀（`15.2.0`），fzf 有（`v0.74.2`） |
| delta | tag 也没有 `v` 前缀 |
| eza | asset 名里**不带版本号**，只有 triple |
| btop | asset 是 `btop-x86_64-unknown-linux-musl.tar.gz`，不是 `btop-x86_64-linux-musl.tbz` |
| neovim | 0.11 起从 `nvim-linux64.tar.gz` 改名为 `nvim-linux-x86_64.tar.gz` |
| node | nodejs.org 用 `x64`，不是 `amd64` 也不是 `x86_64`（所以有独立的 `{node_arch}`） |
| uv | 用 gnu triple 而非 musl |

`fetch.sh` 装完会重新验一次版本号，所以「asset 抓错了但看起来装成功」会被抓住。

---

## 中文显示成豆腐块 / 方块

```bash
fc-cache -f
fc-match "LXGW WenKai Mono"      # 返回 DejaVuSans 就是没装上
./scripts/60-fonts.sh
```

然后**重启终端**。已经开着的窗口不会重新加载字体。

注意别用 `fc-list : family | grep "…Nerd Font Mono"` 来判断 —— fontconfig
报的是缩写族名（`IosevkaTermSlab NF` / `NFM`），跟配置里写的全名对不上，
会误报成缺失。`fc-match` 才是语义正确的检查。

---

## `zsh -i` 有 stderr 输出

`verify.sh` 会把这个报成 WARN。常见的几种：

| 输出 | 原因 |
|---|---|
| `can't change option: zle` | 在非真正交互的上下文里跑 `zsh -i`，atuin/zle 的初始化会抱怨。无害 |
| `compinit: insecure directories` | `~/.local/share/zsh/plugins` 或 `/usr/local/share/zsh` 权限太松。`chmod g-w,o-w <dir>` |
| `command not found: starship` | 20-binaries 没跑成功。`./scripts/20-binaries.sh --only starship` |
| 插件路径相关报错 | `./scripts/40-zsh.sh` 重装插件 |

---

## PATH 里 `~/.local/bin` 出现多次

`verify.sh` 有这条回归测试（GAP-FIX #4）。根因是 uv 生成的
`~/.local/bin/env` 里用的是 `$HOME/.local/share/../bin` 这种拼法，
字符串上不等于 `$HOME/.local/bin`，所以它自己的去重守卫永远不触发。

本仓库的 `.zshrc` 用 `typeset -U path PATH` 解决（zsh 惯用法，让 path
数组自动去重），并把末行的 source 路径归一化。

如果你的 `~/.zshrc` 还是软链之前的旧版本，跑 `./scripts/50-dotfiles.sh`。

---

## `dconf load` 失败

需要活的 DBus 会话。SSH 进来跑会失败（`Cannot autolaunch D-Bus`）。
在图形会话的终端里跑。

如果导入后 GNOME Terminal 里看不到那个 profile，检查
`desktop/gnome-terminal.dconf` 开头有没有 `[legacy/profiles:/]` 段
（含 `list` 和 `default` 两个键）。裸的 `dconf dump` 不含这两个键，
本仓库的导出文件已经补上了。

恢复备份：

```bash
dconf load /org/gnome/terminal/ < ~/.config/ubuntu_workflow/backup/<时间戳>/gnome-terminal.dconf.bak
```

---

## 我改过的配置被覆盖了？

不会被静默覆盖。`50-dotfiles.sh` 在软链之前会把已存在的文件挪到
`~/.config/ubuntu_workflow/backup/<时间戳>/`，并在报告账本里记一行。

```bash
ls -la ~/.config/ubuntu_workflow/backup/
grep backup ~/.cache/ubuntu_workflow/report.tsv
```

落地之后 `~/.zshrc` 是指向仓库的软链，所以**改它就是改仓库文件** ——
`git status` 会显示出来。这是刻意的设计：`git status` 免费变成
「我最近手改过哪些配置」的 diff。

只想在这台机器上生效的改动写 `~/.zshrc.local`（已被 gitignore，
`.zshrc` 末尾会 source 它，所以能覆盖前面的设置）。

---

## apt 锁被占

```
Could not get lock /var/lib/dpkg/lock-frontend
```

后台的 `unattended-upgrades` 在跑。等一两分钟，或者：

```bash
sudo systemctl stop unattended-upgrades
./scripts/10-apt.sh
```

---

## 想在干净环境里试一遍

不改动本机的完整冒烟测试：

```bash
docker run --rm -it -v "$PWD:/repo:ro" ubuntu:22.04 bash -c '
  apt-get update -qq && apt-get install -y -qq git curl sudo ca-certificates >/dev/null
  useradd -m -s /bin/bash test && cp -r /repo /home/test/uw && chown -R test /home/test/uw
  su - test -c "cd ~/uw && ./bootstrap.sh --profile minimal --yes --no-sudo && ./verify.sh --profile minimal"
'
```

容器里没有图形会话，所以 70-desktop 会自动跳过，字体检查会告警 —— 都是预期内的。

---

## 报告账本在哪

```
~/.cache/ubuntu_workflow/report.tsv       每个单元的执行结果
~/.cache/ubuntu_workflow/downloads/       下载缓存（拷到另一台机器可离线安装）
~/.cache/ubuntu_workflow/steps/           步骤内容哈希 stamp
~/.config/ubuntu_workflow/backup/         被替换掉的原文件
```

想强制重跑忽略所有「已安装」判断：`./bootstrap.sh --force`
