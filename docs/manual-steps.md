# 脚本做不了的事

`bootstrap.sh` 跑完之后还剩这些。按重要性排序。

---

## 1. Termius —— 登录账号找回主机

```
打开 Termius → 右上角登录 → 输你的 Termius 账号密码
→ 主机、分组、密钥、代码片段从云端同步下来
```

**为什么不能自动化**：Termius 9.x 把数据存在
`~/.config/Termius/IndexedDB/file__0.indexeddb.leveldb/` 里，是一个 2 MB 左右的
加密 LevelDB。字段名（`label` / `address` / `username` / `private_key`）是明文，
但**值全部加密**，解密密钥由账号密码派生。

搬这个目录过去是行不通的，也不该做：

- 里面混着 `Cookies`（活的登录态）、Crashpad / Sentry 状态、缓存、机器绑定的
  singleton 文件；
- `session-logs-v2/` 下是**明文的终端会话录像**（源机器上有个 2.5 MB 的），
  里面可能有任何你敲过或屏幕上出现过的东西；
- 就算拷过去，vault 仍然需要账号密码才能解锁。

所以本仓库只负责把应用装上（`70-desktop.sh`，走官方 deb），数据靠账号同步。
`.gitignore` 里显式挡掉了 `**/Termius/`。

**替代路径**：Termius 支持从 `~/.ssh/config` 一键导入主机
（Settings → 或新建主机时选 Import）。如果你的机器列表本来就在 ssh config 里，
这条路比云同步更透明。

---

## 2. git 身份

```bash
$EDITOR ~/.gitconfig.local
# 或者
git config --global user.name  "你的名字"
git config --global user.email "you@example.com"
```

`50-dotfiles.sh` 会从 `git/gitconfig.local.example` 初始化一份
`~/.gitconfig.local`（已存在则绝不覆盖），里面是占位值。

**为什么不放进仓库**：这是 public 仓库。

**为什么 `~/.gitconfig` 是生成的而不是软链**：如果软链到仓库文件，那么一条
`git config --global user.email you@example.com` 就会把真实邮箱写进仓库工作树，
下次 `git add -A` 顺手就提交上去了。改成生成一个只含两条 `[include]` 的真实文件后，
所有 `--global` 写入都落在仓库外：

```ini
[include]
	path = <repo>/git/gitconfig      # 工具链配置，跟着 git pull 更新
[include]
	path = ~/.gitconfig.local        # 你的身份，不进版本库
```

---

## 3. 换默认登录 shell

```bash
chsh -s "$(command -v zsh)"
```

`40-zsh.sh` 会问你要不要改（用已经拿到的 sudo 凭据执行 `sudo chsh`，
不再单独问一次密码）。

**⚠️ 改完必须完整注销重新登录。** 开一个新的终端标签页、`exec zsh`、
重启终端模拟器都不算 —— 登录 shell 是登录会话建立时读的。
这是「怎么改了没生效」的头号原因。

想临时试试不用改登录 shell：直接 `zsh -l`。

---

## 4. 字体

`60-fonts.sh` 会下载并跑 `fc-cache -f`。但：

- **已经开着的终端要重启**才认新字体；
- 验证方式不是 `fc-list : family | grep`（fontconfig 报的是缩写族名
  `IosevkaTermSlab NFM`，跟配置里写的全名对不上），而是：
  ```bash
  fc-match "IosevkaTermSlab Nerd Font Mono"
  # 返回 IosevkaTermSlabNerdFontMono-Regular.ttf 才是有；
  # 返回 DejaVuSans.ttf 说明没装上，fontconfig 回落了
  ```

默认只装 2 款（约 120 MB）：`IosevkaTermSlab`（ghostty 的主字体）和
`LXGW WenKai Mono`（中文 fallback）。`--fonts full` 装全部 7 款，约 1.6 GB。

**minimal 集下有个看起来像 bug 的东西**：
`~/.config/fontconfig/conf.d/99-cjk-serif-mono.conf` 给三款 Nerd Font
（IosevkaTermSlab / MonaspiceXe / CodeNewRoman）都配了中文 fallback 规则。
minimal 只装第一款，所以另两条规则处于惰性状态。无害，是刻意的。

---

## 5. GNOME Terminal 配色（可选）

```bash
dconf load /org/gnome/terminal/ < desktop/gnome-terminal.dconf
```

**⚠️ 这会替换 GNOME Terminal 的全部 profile，不是新增一个。**
`70-desktop.sh` 会先自动 `dconf dump` 备份到
`~/.config/ubuntu_workflow/backup/<时间戳>/`，然后才问你要不要导入。

导出的文件里包含了 `[legacy/profiles:/]` 的 `list` 和 `default` 键，
所以导入后 profile 会被正确注册（裸的 `dconf dump` 不含这两个键，
导入后 GNOME Terminal 看不到那个 profile —— 这里补上了）。

需要活的 DBus 会话，SSH 进来跑会失败。

---

## 6. Ghostty 的来源，需要你知情

`ghostty` snap 的打包者是 **`ken-vandine`，不是 Ghostty 官方**
（Ghostty 项目自己不发 deb 或 snap）。而且是 **classic confinement**，
意味着它对整个系统有完全访问权限，跟普通 apt 包一样。

`70-desktop.sh` 会在装之前把这段告诉你并要一次确认。不接受的话：

- 用 GNOME Terminal（本仓库也带配色），或
- 从源码编译 Ghostty（需要 Zig），或
- 换任何别的终端 —— 这套配置的其余部分不依赖 Ghostty。

---

## 7. 中文输入法（本仓库不管）

源机器用的是 fcitx5。没纳入仓库，因为它牵涉系统级的环境变量和
桌面会话，跟「终端环境」不是一回事。要的话：

```bash
sudo apt install -y fcitx5 fcitx5-chinese-addons fcitx5-config-qt
# 然后写 ~/.config/environment.d/fcitx5.conf：
#   GTK_IM_MODULE=fcitx
#   QT_IM_MODULE=fcitx
#   XMODIFIERS=@im=fcitx
# 注销重登
```

---

## 8. 一些不影响使用但值得知道的

- **`gh` 是 credential helper** —— `git/gitconfig` 里设了
  `credential.https://github.com.helper = !gh auth git-credential`。
  不跑 `gh auth login` 的话，https 推送会没凭据（用 SSH 就没这问题）。
- **atuin 默认纯本地** —— `auto_sync = false`。要跨机同步历史需要自己
  `atuin register` / `atuin login`。它的 `history_filter` 已经配好了，
  会拦掉 `pass` / `AWS_SECRET_ACCESS_KEY` / `export *TOKEN=` 之类的命令。
- **`bat` 的主题** —— `20-binaries.sh` 装完会跑 `bat cache --build`，
  让它认出 `~/.config/bat/themes/` 里的 4 个 Catppuccin tmTheme。
  手动装 bat 的话别忘了这一步，否则 `--theme="Catppuccin Mocha"` 会报未知主题。
