# AGENTS.md —— 给 coding agent 的运行手册

你在一台新 Ubuntu 机器上，手里有这个仓库。目标：把这套终端环境装起来。
本文件是给模型看的操作说明，不是给人看的介绍（那个在 `README.md`）。

---

## 0. TL;DR —— 90% 的情况按这个走

```bash
./bootstrap.sh --dry-run --profile desktop   # 永远先跑这个
./bootstrap.sh --profile desktop             # 实跑
./verify.sh                                  # 验收
```

跑完把 `docs/manual-steps.md` 里的内容念给人听 —— 有几件事脚本做不了。

---

## 1. 这个仓库是什么 / 不是什么

**是**：在全新 Ubuntu 22.04+ x86_64 上复现一套 zsh + starship + Gruvbox Dark
的终端环境。手写 `.zshrc`（无框架）、5 个 zsh 插件、16 个钉死版本的工具、
Ghostty 终端、Nerd Font + 霞鹜文楷。

**不是**：SSH 配置、密钥、git 身份、Termius 的主机数据、dotfile 同步工具。

**铁律**：任何含真实邮箱、主机名、内网 IP、token、密钥的东西，一律不准提交。
这是 public 仓库。`./verify.sh --hygiene` 会扫这些，CI 也会。

---

## 2. Preflight —— 动手前先确认

`00-preflight.sh` 会自动查下面这些，但你自己心里也要有数：

| 检查 | 不满足时怎么办 |
|---|---|
| `lsb_release -is` 是 Ubuntu/Debian | 不是就停下来问人。apt 包名和 snap 都对不上 |
| `uname -m` 是 x86_64 | aarch64 大体可用（manifest 有对应 triple），但没验证过，告知人 |
| 有 `$DISPLAY` / `$WAYLAND_DISPLAY` / `$XDG_SESSION_TYPE` | 都没有 = headless，用 `--profile minimal`，GUI 步骤会自动跳过 |
| 不是 WSL / 容器 | 是的话步骤 70 自动跳过 |
| `$HOME` 剩余 ≥ 2GB | full 字体集要 3GB+ |
| `curl -fsI https://github.com` 通 | 不通就停 —— 所有工具都从 GitHub releases 下载。有代理先 `export https_proxy=` |

---

## 3. 开跑前一次性问人的问题

**把下面这些放在同一条消息里问完**，然后就可以无人值守跑完：

- **Q1 sudo** —— 有没有 sudo 权限？（apt / snap / chsh 需要。没有就加 `--no-sudo`，
  仍能在 `~` 下装出一套完整可用的终端环境）
- **Q2 profile** —— `minimal`（只有终端）还是 `desktop`（+ Ghostty + Termius）？
- **Q3 字体** —— `minimal`（2 款，约 120MB）还是 `full`（7 款，约 1.6GB）？
- **Q4 git 身份** —— user.name 和 user.email 是什么？
- **Q5 登录 shell** —— 要不要把 zsh 设成默认登录 shell？
- **Q6 GNOME Terminal** —— 要不要导入配色？（**会覆盖现有全部 profile**）

### 关于 Q4，三条硬规则

1. **绝不猜**。不知道就跳过，让人之后自己填。
2. **绝不跑 `git config --global user.email`** —— 写进 `~/.gitconfig.local`。
3. **绝不把身份写进本仓库任何文件**。`git/gitconfig` 里永远不该有 `[user]` 段。

---

## 4. 步骤表

| # | 脚本 | sudo | 联网 | 可跳过 | 干什么 |
|---|---|:--:|:--:|:--:|---|
| 00 | preflight | 软 | ✓ | ✗ | 环境断言、装 jq、校验 manifest |
| 10 | apt | **✓** | ✓ | ✓ | 一次批量装 20 个系统包 |
| 20 | binaries | ✗ | ✓ | ✗ | 13 个静态二进制 → `~/.local/bin` |
| 30 | runtimes | ✗ | ✓ | ✓ | node20 + neovim + uv 托管 python |
| 40 | zsh | 部分 | ✓ | ✗ | 5 个插件 clone 到钉死 sha；chsh |
| 50 | dotfiles | ✗ | ✗ | ✗ | `home/` 下配置落地 |
| 60 | fonts | ✗ | ✓ | ✓ | 下载字体 + fc-cache |
| 70 | desktop | **✓** | ✓ | ✓ | Ghostty snap、Termius deb、dconf |
| 99 | summary | ✗ | ✗ | ✓ | 汇总 + 手动步骤 |

单跑某一步：`./scripts/20-binaries.sh`
单跑某一个工具：`./scripts/20-binaries.sh --only eza`

---

## 5. 退出码 —— 直接分支，不要解析散文

| 码 | 含义 | 你该做什么 |
|---|---|---|
| 0 | 全好 | 报告成功，念手动步骤 |
| 1 | 用法错 / preflight 失败 | 停下，看输出，问人 |
| 2 | 有 `required:false` 的项失败 | 告知人哪些可选项没装上，继续 |
| 3 | 有 `required:true` 的项失败 | **停下**，跑 `./verify.sh` 诊断 |

`verify.sh` 用同一套码（0 / 2 warn / 3 fail），`--json` 输出结构化结果。

---

## 6. 部分失败怎么处理

1. 读 `~/.cache/ubuntu_workflow/report.tsv`，找 `status=fail` 的行。
2. **下载失败 ≈ 上游改了 release asset 名**（本仓库预期的头号失败模式）。流程：
   ```bash
   ./bootstrap.sh --dry-run          # 对每个 URL 发 HEAD，直接指出哪个 404
   ```
   然后去上游 releases 页面看新的 asset 名，改 `manifest/tools.json` 的
   `version` / `github.asset`，再 `./scripts/20-binaries.sh --only <id>`。

   **把改动的 pin 报告给人。不准静默升大版本。**
   （真实案例：nvim 0.11 把 `nvim-linux64.tar.gz` 改成了 `nvim-linux-x86_64.tar.gz`；
   ripgrep 的 tag 没有 `v` 前缀而 fzf 有 —— 这类差异都在 manifest 里显式写着。）
3. `snap: command not found` → 系统没 snapd，跳过步骤 70，告知人。
4. apt 锁被占 → 等一会儿重试一次，再不行报告。

---

## 7. 验证 —— 这一节最重要

**不要用你自己 shell 里的 `command -v` 去验证工具是否安装。**

你的 harness 可能注入了 shell 函数（Claude Code 就注入了一个叫 `rg` 的函数，
即使 PATH 上根本没有 ripgrep 二进制，`command -v rg` 也会成功）。
而且这套配置的 `.zshrc` 给 `cat` / `find` / `grep` / `top` 都加了别名。

用 `./verify.sh`。它内部一律用 `type -P`（bash builtin，只查 PATH，忽略函数和
别名），版本命令跑在 `env -i` 的干净环境里。真要手查就用：

```bash
PATH=/usr/bin:/bin type -P rg      # 对
command -v rg                       # 错，会骗你
```

同理字体不能用 `fc-list : family | grep` 查 —— fontconfig 报的是缩写族名
（`IosevkaTermSlab NFM`），跟配置里写的全名对不上。用 `fc-match "<全名>"`
看返回的是不是它本身（要不到会回落到 DejaVu Sans）。

最后一道：`zsh -i -c 'echo OK'` 必须打出 OK 且 **stderr 为空**。
这一条能同时抓到插件加载失败、starship 缺失、compinit 权限告警。

---

## 7.5 给 manifest 加新工具时

最容易踩的两个坑，都是 docker 冒烟测试抓出来的：

1. **`id` 和实际二进制名不一致时必须写 `"as"`。**
   `install_binary_from_url` 默认按 `--name`（即 manifest 的 `id`）命名安装后的
   文件。清单里目前只有 ripgrep 是这种情况（`id: ripgrep` / 二进制 `rg`），
   它有 `"as": "rg"`。漏了的话表现为「装完却跑不起来」。
2. **`verify.regex` 要对着工具的真实输出写。**
   有些工具的 `--version` 带 ANSI 颜色码（btop 就是），版本号还可能带
   `+githash` 后缀。`uw_probe_version` 已经统一剥 ANSI，但正则本身也别写太死。

加完新工具后跑一遍 `docs/troubleshooting.md` 里的 docker 冒烟测试 ——
在一台已经配好的机器上，这两个坑都测不出来。

---

## 8. 禁止事项

- **不问就 `chsh`**（Q5）。且要告诉人：改完必须**完整注销重登**，开新标签页没用。
- **不问就 `dconf load`**（Q6）。它会替换 GNOME Terminal 的**全部** profile，不是新增。
- **不要为了修本机问题去改 `home/` 下的文件**。机器专属配置写 `~/.zshrc.local`
  （已被 gitignore）。改 `home/.zshrc` 意味着「所有机器都要这么改」。
- **不要引入新的包管理器**（brew / nix / stow / chezmoi / yadm / pipx）。
  刻意不用它们：静态二进制 + 软链已经够了，多一个包管理器就多几个 GB 和一层抽象。
- **`scripts/` 里不准直接写 `sudo`**。提权一律走 `lib/common.sh` 的 `sudo_run()`。
  可审计不变量（CI 里也跑这条）：
  ```bash
  grep -rnE '(^|[^_[:alnum:]])sudo ' scripts/ \
    | grep -vE '(:[0-9]+:[[:space:]]*#)|printf|echo|err |warn |info '
  ```
  应当零命中 —— 剩下的都是注释和提示文案里的字面量。
- **不要把 `~/.gitconfig` 软链到仓库**。必须是 `50-dotfiles.sh` 生成的、只含两条
  `[include]` 的真实文件 —— 否则一条 `git config --global user.email` 就把真实邮箱
  写进 public 仓库的工作树了。

---

## 9. 收尾时该告诉人什么

```
装好了：<列表>
跳过了：<列表及原因>
失败了：<列表及重跑命令>

还需要你手动做：
  1. 打开 Termius，登录账号 —— 主机和密钥从云端同步（本仓库只装应用）
  2. 编辑 ~/.gitconfig.local 填 git 身份
  3. 换了登录 shell 的话，完整注销重登
  4. 重启已经开着的终端，让它认新字体

验证：./verify.sh
```
