# ubuntu_workflow

> 开 Ubuntu 新机的终端配置。`git clone` 之后 `./bootstrap.sh`，
> 或者直接把仓库交给 Claude Code —— 它读 `AGENTS.md` 自己配。

一套 zsh + Starship + Gruvbox Dark 的终端环境，从一台跑了几个月的
Ubuntu 22.04 工作机上原样固化下来，配上钉死版本的清单和幂等脚本。

---

## 快速开始

```bash
git clone https://github.com/Asada-Sinon/ubuntu_workflow.git
cd ubuntu_workflow
./bootstrap.sh --dry-run     # 先看计划，顺便检查所有下载链接还活着
./bootstrap.sh               # 实跑
./verify.sh                  # 验收
```

没有 sudo 也能装（全部落在 `~` 下）：`./bootstrap.sh --no-sudo`

---

## 验证状态

**已在全新的 `ubuntu:22.04` 容器里跑通全流程**（2026-08-03，commit `bfa325f`）。
测的是真实路径：从 GitHub `git clone`，不是挂载本地目录。

容器基线是一台真白机 —— `zsh git curl jq tmux fzf rg fd bat eza starship node python3`
**一个都没有**。

| 环节 | 退出码 | 结果 |
|---|:--:|---|
| `bootstrap --dry-run` | **0** | 24 成功 · 1 跳过 · **0 失败**，26 个下载 URL 全部可达 |
| `bootstrap`（minimal） | **0** | 59 成功 · 3 跳过 · **0 失败** |
| `verify` | 2 | 50 ok · 2 warn · **0 fail**（两条 warn 见下） |
| 幂等性（再跑一遍） | **0** | 命中 32 处「已存在」跳过 |
| 端到端断言 | — | **28 / 28 通过** |

`verify` 返回 2 是容器环境的正常结果，两条 warn 都不是 bug：git 身份未填写
（刻意不自动填、不猜），以及 `docker run` 不带 `-t` 没有 TTY 导致
`zsh -i` 里有东西调 `tput` 报了一句 —— 真实终端里不会出现。

其中被显式断言验证过的关键行为：

- 执行 `git config --global user.email` 之后**仓库工作树仍然干净** ——
  证明 `~/.gitconfig` 用 generate 而非软链，确实挡住了身份写进 public 仓库
- 交互式 zsh 的 `$PATH` 里 `~/.local/bin` **恰好出现一次**（GAP-FIX #4）
- `zsh -i` 正常启动、5 个插件全部 clone 到钉死的 commit sha
- 三处 GAP-FIX 全部到位：nvim 已装、rg 已装、`.tmux.conf` 存在且语法正确
- 容器环境被正确识别，70-desktop 整步跳过

### 这个测试抓到了 5 个问题

不是走过场。**每一个都只在全新机器上才会暴露** —— 在一台已经配好的机器上
（比如固化这套配置的那台）全都测不出来：

| 问题 | 症状 | 为什么本机测不出 |
|---|---|---|
| jq 自举失效 | `--dry-run` 直接崩，退出码 1 | 本机早有 jq。而这是 `AGENTS.md` 让 agent 跑的**第一条命令** |
| ripgrep 装错文件名 | 装成 `~/.local/bin/ripgrep`，验证命令却是 `rg --version` | 全清单唯一 id≠二进制名的条目，而本机根本没装 rg |
| btop 版本探测失败 | `--version` 输出带 ANSI 颜色码，正则卡住 | 本机没装 btop |
| dry-run 假警报 | 健康新机也返回退出码 2 | 本机 uv/zsh 都在，触发不了「上游步骤尚未执行」那个分支 |
| GitHub 限流没重试 | 一次 403 就让整个 bootstrap 以 rc=3 告终 | 连拉 16 个二进制才撞得上 |

前四个有个共同规律：**都出在「本机恰好已经有、因此从没被真实执行过」的代码路径上**。
详见 `git log`（`610571c`、`ddddb80`、`bfa325f`）。

复现方法见 [`docs/troubleshooting.md`](docs/troubleshooting.md#想在干净环境里试一遍) ——
**改完 `manifest/` 或 `lib/` 之后建议跑一遍**。

---

## 装出来是什么样

- **配色** —— Gruvbox Dark 全家桶：zsh 语法高亮、starship、fzf、bat、
  delta、btop、tmux、Ghostty、GNOME Terminal 全部同一套色板
- **提示符** —— Starship powerline：
  `os → 用户名 → 目录 → git 分支/状态 → 语言版本 → docker/conda → 时间`，
  命令跑超过 2 秒自动显示耗时
- **字体** —— IosevkaTermSlab Nerd Font Mono（衬线等宽）+ 霞鹜文楷等宽做中文
  fallback，中文是带笔锋的楷体
- **补全** —— fzf-tab 接管 tab 菜单，目录预览用 eza、文件预览用 bat
- **历史** —— 10 万行，多终端共享；`Ctrl-R` 走 atuin 模糊搜索（上箭头保留 zsh 原生行为）
- **导航** —— `z foo` 智能跳目录，`zi` 用 fzf 交互选
- **替换掉的老命令** —— `ls`→eza（带图标和 git 状态）、`cat`→bat、`find`→fd、
  `grep`→rg、`top`→btop、git 分页器→delta（并排 diff）

启动开销约 0.15 秒。

---

## 这套环境的取舍

**shell 不用框架。** 没有 oh-my-zsh / zinit / zplug / powerlevel10k。
就是一个 12 KB 的手写 `~/.zshrc`，全中文注释，每一行都知道在干什么。
5 个插件手动 `git clone` 到 `~/.local/share/zsh/plugins`，在 `.zshrc` 里按正确顺序
`source`（fzf-tab 必须在 compinit 之后、语法高亮必须在最后）。
机器私有配置放 `~/.zshrc.local`，不进版本库。

**工具不走 apt。** jammy 的包太旧 —— 它的 `gh` 还是 2022 年的 2.4.0。
所有现代 CLI 都是从 GitHub releases 下载的单文件静态二进制，扔进 `~/.local/bin`，
版本在 `manifest/tools.json` 里钉死。优先用 musl 静态版，免疫 glibc 版本问题。

**不引第二个包管理器。** 没有 brew、nix、stow、chezmoi、yadm、pipx。
静态二进制 + 软链已经够了，多一个包管理器就多几个 GB 和一层抽象。

**Python 只用 uv。** 没有 pip、pipx、conda、pyenv。
Node 手装 20.x 到 `~/.local/opt/node20`（Ubuntu 22.04 的 apt 只有 node 12）。

---

## 目录结构

```
bootstrap.sh          唯一入口
verify.sh             doctor：逐项检查是否真的到位
AGENTS.md             给 coding agent 的运行手册（CLAUDE.md 软链到它）

manifest/
  tools.json          ★ 唯一事实来源：每个工具的版本、下载方式、验证命令
  zsh-plugins.json    5 个插件 + 钉死的 commit sha
  fonts.json          字体族，分 minimal / full 两组
  dotfiles.tsv        只登记「不走默认软链」的少数条目

lib/
  common.sh           日志、run/sudo_run、报告账本、版本探测
  fetch.sh            ★ 下载 + 解包 + 原子安装（16 个工具共用这一段）
  link.sh             link / copy / generate / append 四种落地方式

scripts/00…99         按序执行的步骤，每个都可单独重跑
home/                 严格镜像 $HOME 的配置树
git/gitconfig         git 工具链配置（零身份信息）
desktop/              GNOME Terminal 的 dconf 导出
docs/                 清单、手动步骤、排错
```

`home/` 严格镜像 `$HOME`，所以 `home/X` → `~/X` 的映射是可推导的 ——
加一个新配置文件只要放对位置，不用改任何登记表。

---

## 仓库里没有什么

| 没有 | 为什么 |
|---|---|
| SSH 配置和密钥 | 不在本仓库范围内 |
| git 身份（name / email） | 这是 public 仓库。身份在 `~/.gitconfig.local` |
| Termius 的主机数据 | 它存在 `~/.config/Termius/` 的加密 IndexedDB 里，不可移植。只能靠账号云同步 |
| 字体二进制 | 源机器上共 1.6 GB。脚本从上游下载 |
| 任何 token / 密码 / 内网主机名 | `./verify.sh --hygiene` 会扫，CI 也会 |

---

## 必须手动做的事

脚本做不到的，就这几件：

1. **Termius** —— 装好后打开应用，**登录你的 Termius 账号**，主机、密钥、
   代码片段会从云端同步下来。本仓库只负责把应用装上。
2. **git 身份** —— 编辑 `~/.gitconfig.local` 填 `user.name` / `user.email`。
3. **换登录 shell** —— `chsh` 要输密码，而且改完**必须完整注销重新登录**才生效。
   开一个新的终端标签页是没用的（这是最常见的「怎么没生效」）。
4. **GNOME Terminal 配色** —— `dconf load` 会替换**全部** profile，不是新增一个。
   脚本会先自动备份，但仍需你明确同意。
5. **Ghostty 是 snap classic 包**，打包者 `ken-vandine`，**不是 Ghostty 官方**
   （官方不发 deb/snap）。classic confinement 意味着它对整个系统有完全访问权限。
6. **字体** —— 装完执行 `fc-cache -f`（脚本会做），但已经开着的终端要重启才认。

完整清单：[`docs/manual-steps.md`](docs/manual-steps.md)

---

## 顺手修掉的源机器问题

固化的时候发现这台跑了几个月的机器上有几处配置和实际对不上。都修了，
如实记在这儿：

| # | 原状 | 为什么是 bug | 现在怎么处理 |
|---|---|---|---|
| 1 | `.zshrc` 写死 `EDITOR=vim`，但 **vim 和 nvim 都没装** | `git commit` 不带 `-m`、`alias zshrc`、`fc` 全部直接失败 | 装 neovim；`.zshrc` 改成 `nvim → vim → vi` 按序探测 |
| 2 | `alias grep='rg'` 被 `command -v rg` 守卫着，但 **ripgrep 从没装过** | 这条别名一直是死的，从来没生效 | 装 ripgrep，别名真正生效。注意 rg 和 grep 参数不完全兼容，脚本里请写 `command grep` |
| 3 | tmux 3.2a 装了但 **零配置** | 没有 `.tmux.conf`、没有 tpm，等于裸奔 | 补一份跟全局同套配色的 `.tmux.conf`，不依赖 tpm |
| 4 | `~/.local/bin` 被 prepend 到 PATH **四次** | `.profile` / `.profile` source 的 `env` / `.zshrc` / `.zshrc` 末尾再 source 一次。根因是 uv 生成的 `env` 用 `$HOME/.local/share/../bin` 这种拼法，字符串上不等于 `$HOME/.local/bin`，它自己的去重守卫永远不触发 | 加 `typeset -U path PATH`；末行路径归一化。`verify.sh` 里有这条的回归测试 |

`verify.sh` 会逐条检查这四项，所以它们不会悄悄退化回去。

---

## 常用命令

| 命令 | 作用 |
|---|---|
| `./bootstrap.sh --dry-run` | 打印计划，并对每个下载 URL 发 HEAD —— 顺带就是链接腐烂检查器 |
| `./bootstrap.sh --profile minimal` | 只装终端，不碰 GUI（headless / 服务器） |
| `./bootstrap.sh --no-sudo` | 零提权，全部装在 `~` 下 |
| `./bootstrap.sh --only 20,50` | 只跑指定步骤 |
| `./scripts/20-binaries.sh --only eza` | 只重装一个工具 |
| `./verify.sh` | 逐项体检 |
| `./verify.sh --json` | 结构化输出，给 agent 消费 |
| `./verify.sh --hygiene` | 只跑仓库卫生检查（邮箱 / 私钥 / 大文件） |

### shell 里的别名

`ls la ll lt` (eza) · `cat` (bat) · `find` (fd) · `grep` (rg) · `top` (btop) ·
`g gs gd gds ga gc gcm gp gl glog` (git) · `..` `...` `....` ·
`mkcd` 建目录并进去 · `extract` 万能解压 · `fkill` fzf 选进程杀掉

---

## 升级钉死的版本

```bash
./bootstrap.sh --dry-run        # 先确认现有 URL 还活着
# 改 manifest/tools.json 里的 version（必要时改 github.asset）
./scripts/20-binaries.sh --only <id> --force
./verify.sh
```

上游改 asset 名是最常见的失效原因（nvim 0.11 就把 `nvim-linux64.tar.gz`
改成了 `nvim-linux-x86_64.tar.gz`）。`fetch.sh` 装完会重新验一次版本号，
所以「装错了东西但看起来成功」会被抓住，不会静默通过。

---

## 排错

见 [`docs/troubleshooting.md`](docs/troubleshooting.md)。最常见的三个：

- **改了登录 shell 但没生效** → 要完整注销重登，不是开新标签页
- **终端里中文显示成豆腐块** → `fc-cache -f` 然后重启终端
- **`command -v rg` 说装了但其实没有** → 你的 shell 里有同名函数或别名。
  用 `PATH=/usr/bin:/bin type -P rg`，或直接 `./verify.sh`

---

## English summary

Reproducible terminal environment for a fresh Ubuntu box: hand-written zsh config
(no framework), Starship prompt, 16 version-pinned static binaries in
`~/.local/bin`, 5 zsh plugins pinned to commit SHAs, Ghostty terminal, Nerd Font +
CJK font pairing, all themed Gruvbox Dark.

Run `./bootstrap.sh --dry-run` then `./bootstrap.sh`, or hand the repo to a coding
agent — `AGENTS.md` is the runbook. `./verify.sh` checks every item and exits
0 / 2 / 3 for clean / warnings / failures.

**Verified end-to-end in a clean `ubuntu:22.04` container** (cloned from GitHub,
not bind-mounted): dry-run `rc=0`, bootstrap `rc=0` (59 ok · 3 skipped · 0 failed),
28/28 assertions passed, re-run idempotent. That run caught 5 real bugs that were
invisible on an already-configured machine — see 验证状态 above.

Contains no SSH config, no git identity, no secrets, no font binaries.
Docs are Chinese-primary.
