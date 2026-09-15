# 发布到 AUR —— 操作指南与收益说明

> ## ⏸️ 当前状态：AUR 暂停新账号注册，暂时无法上架
>
> **2026-06-15 起**，Arch 官方因「恶意软件包事件」（约 1500+ 个 AUR 包被投毒）
> **暂停了新账号注册**。官方公告明确说明：
>
> - 这是**平台级临时措施**，与你和你的网络无关
> - **没有人工注册队列**，发邮件申请也无效
> - **不要写脚本轮询注册页**，恢复消息只会发布在
>   [aur-general](https://lists.archlinux.org/mailman3/lists/aur-general.lists.archlinux.org/)
>   与 [Arch 新闻](https://archlinux.org/news/)
>
> 截至本文更新（2026-09-15）已关闭 **92 天**，Arch 新闻里**没有任何恢复公告**。
> AUR 本身运转正常（已有账号可正常提交与更新），**仅新注册被冻结**。
>
> **结论：这件事只能等，且完全不影响你现在分发软件**（见第四节）。
> 其余准备工作已全部完成，注册一恢复即可按第五节推送。

本文档说明 hifi4linux 发布到 AUR（Arch User Repository）的**实际收益**、
**已经为你准备好的东西**，以及**你要亲手做的几步**。

---

## 一、先说收益：为什么值得发

AUR 不是一个"应用商店"，它是 **Arch 生态里所有第三方软件的默认分发渠道**。
Arch / CachyOS / EndeavourOS / Manjaro 用户装非官方软件，第一反应就是
`paru <包名>` 或 `yay <包名>`。发到 AUR 等于接入了这个渠道。

具体到 hifi4linux：

| 收益 | 说明 |
|---|---|
| **安装从 4 步变 1 步** | 现在是 `git clone` → `cd` → `./install.sh --deps` → 手动确认。发 AUR 后是 `paru -S hifi4linux`，依赖自动装、文件自动放系统路径、升级自动跟随 |
| **进入搜索结果的默认视野** | 你的目标用户（Linux HiFi 玩家）大多用 Arch 系。他们搜 "bit perfect player" 时，`paru -Ss hifi` 就能看到你 —— 不需要先发现你的 GitHub |
| **获得 AUR 的信任标签** | AUR 页面上有投票数、最后更新时间、依赖列表。有人投票后，后来者会认为"这东西有人用、没坏"，这比 GitHub star 更能促成安装 |
| **升级推送免费** | 用户 `paru -Syu` 时，如果 AUR 包更新了，会自动一起升级。你不需要通知任何人 |
| **不收编、不审查、不收费** | AUR 只托管 PKGBUILD 文本（不含二进制），你保留全部控制权，随时可删 |
| **对项目的信号价值** | "有 AUR 包"是 Linux 桌面项目成熟的标志之一，README 里挂个 AUR 徽章会显著提升可信度 |

**成本**：几乎没有。PKGBUILD 已经写好并验证过；每次发新版只需改 `pkgver` 重新生成 `.SRCINFO` 推一次（见第五节）。

**要注意的现实**：AUR 包是**用户本机编译**的，不是你上传二进制。所以发布的是
"配方"而不是"成品"——这也意味着没有任何构建服务器成本。

---

## 二、已经为你准备好的东西

以下内容已在本仓库中完成并**实测验证**（不是纸面配置）：

| 文件 | 状态 | 说明 |
|---|---|---|
| `PKGBUILD` | ✅ 已验证可构建 | 见下方"已修复的问题" |
| `.SRCINFO` | ✅ 已生成 | AUR **强制要求**此文件，网页与 paru 都读它；少了会拒收 |
| `.github/workflows/ci.yml` | ✅ 已配置 | push 时自动跑 bash -n / shellcheck / py_compile / QML 解析 / PKGBUILD 校验 / 包内容断言 |
| `v1.0.0` tag | ✅ 已创建（本地） | 切到 tag 时 `pkgver()` 稳定输出干净的 `1.0.0` |

### 已修复的问题（这些如果不修，发出去就是坏包）

打包过程中实测发现并修掉了 4 个真实缺陷：

1. **`usr/share/applications` 未创建** → `makepkg` 在打包阶段直接失败。
   本地 `install.sh` 因为自己 `mkdir` 过所以没暴露这个问题。
2. **路径硬编码 `$HOME/.local`** → 原脚本写死
   `BACKEND="$HOME/.local/bin/musicd.py"`，而包把文件装到
   `/usr/lib/hifi4linux/`。**结果是包能装上、能启动，但找不到自己的后端**
   —— 这是最典型的"装了没用"型缺陷，用户只会说一句"打不开"就卸载。
   现在脚本改为「本地优先、回退系统路径」探测，打包时再显式收窄到包内路径，
   并用 `grep` 断言注入成功（源码若改了写法，打包会立刻失败而不是发出坏包）。
3. **依赖不全** → 脚本实际调用了 `curl` 和 `notify-send`，但都没声明。
   `pactl` 由 `libpulse` 提供（不是 `pulseaudio-utils`），已相应替换。
4. **`pkgver()` 产生 `1.0.0.r0.gba6941f`** → 发布版应该是干净的 `1.0.0`。
   现已按「tag 上取 tag 号 / tag 之后加 `.rN.gHASH`」区分处理。

### 实测验证记录

- `makepkg` 完整构建成功，产物 `hifi4linux-1.0.0-1-any.pkg.tar.zst`（48 KB）
- 包内容逐项断言通过（9 个关键文件全部就位，无占位符残留）
- **启动打包版 `musicplayer` 实测**：后端被正确拉起
  （日志 `musicd: 曲库 333 首，服务端口 8787`），`/state` 接口正常返回 JSON
- `shellcheck -S warning` 对全部脚本零告警；`py_compile` 通过

---

## 三、你要亲手做的（我做不了的部分）

发布到 AUR 需要**你本人的 AUR 账号与 SSH 密钥**，这两样只能由你操作。

### 第 1 步：注册 AUR 账号

1. 打开 <https://aur.archlinux.org/register/>
2. 用户名建议用 **`brucelvwenhe`**（与 GitHub 一致，便于别人对照）
3. 邮箱填你在用的，收到验证邮件后点确认
4. 记住用户名和邮箱——下面要写进 PKGBUILD

### 第 2 步：生成并上传 SSH 公钥

AUR 用 SSH 密钥认证推送，不是密码。

```bash
# 1) 生成密钥（如果 ~/.ssh 还没有；本机目前没有 ~/.ssh 目录）
ssh-keygen -t ed25519 -C "aur" -f ~/.ssh/aur

# 2) 打印公钥
cat ~/.ssh/aur.pub
```

复制输出的整行，粘贴到 <https://aur.archlinux.org/account/> 的
**SSH Public Key** 栏，保存。

然后配置 SSH（避免每次指定密钥）：

```bash
cat >> ~/.ssh/config <<'EOF'
Host aur.archlinux.org
    IdentityFile ~/.ssh/aur
    User aur
EOF
chmod 600 ~/.ssh/config
```

**顺便**：`~/.ssh` 目前不存在，说明你还没有任何 SSH 密钥。这是备份脚本里
"跳过不存在的路径：/home/bruce/.ssh" 的原因。建好之后下次备份会自动包含它。

### 第 3 步：验证认证通了

```bash
ssh -T aur.archlinux.org
# 期望输出类似：
#   Welcome, brucelvwenhe. You are now authenticated...
```

### 第 4 步：把 PKGBUILD 里的维护者改成你的邮箱

打开 `PKGBUILD`，第一行现在是：

```bash
# Maintainer: brucelvwenhe <https://github.com/brucelvwenhe>
```

AUR 要求格式为 `# Maintainer: 用户名 <邮箱>`，**必须改成真实邮箱**：

```bash
# Maintainer: brucelvwenhe <你的邮箱@example.com>
```

### 第 5 步：推送代码与 tag 到 GitHub

```bash
cd ~/Projects/hifi4linux
git push origin main
git push origin v1.0.0        # tag 必须先推上去，PKGBUILD 的源要能取到
```

### 第 6 步：推到 AUR

```bash
cd ~/Projects/hifi4linux

# AUR 仓库是独立于 GitHub 的另一个 git 仓库
git clone ssh://aur@aur.archlinux.org/hifi4linux.git /tmp/aur-hifi4linux

# 只把这两个文件放进去（AUR 只收 PKGBUILD 与 .SRCINFO）
cp PKGBUILD .SRCINFO /tmp/aur-hifi4linux/

cd /tmp/aur-hifi4linux
git add PKGBUILD .SRCINFO
git commit -m "hifi4linux 1.0.0-1 — 初始提交"
git push origin master
```

推送成功后，包就会出现在 <https://aur.archlinux.org/packages/hifi4linux>。

### 第 7 步：立刻自测一次真实安装

在你的机器上（**先卸掉本地 `~/.local` 那份**，否则会混装）：

```bash
paru -S hifi4linux
musicplayer
```

这一步很重要：AUR 是用户本机编译，你要确认"从零开始"的路径也是通的。

---

## 四、不等 AUR，现在就能让别人装上

这是最重要的一节。**AUR 只是"更方便"，不是"能不能装"** —— 注册关闭期间，
下面这些渠道全部可用，而且其中第一条（GitHub Release）本来就该有。

### 4.1 建一个 GitHub Release（最该做，5 分钟）

现在只有 tag，没有 Release。Release 是别人点进仓库第一眼看到的东西，
也是"这是个正式版本"的信号。

```bash
cd ~/Projects/hifi4linux

# 用 gh（若已装并登录）
gh release create v1.0.0 \
  --title "hifi4linux v1.0.0 — 首个正式发布" \
  --notes-file <(cat <<'EOF'
## 安装

### Arch / CachyOS / EndeavourOS / Manjaro
```bash
git clone https://github.com/Brucelvwenhe/hifi4linux.git
cd hifi4linux && ./install.sh --deps
```

### Debian / Ubuntu
```bash
sudo apt install mpv ffmpeg python3 qml6-module-qtquick-controls pulseaudio-utils
git clone https://github.com/Brucelvwenhe/hifi4linux.git
cd hifi4linux && ./install.sh --no-plasma
```

## 亮点
- 独占 USB DAC（ALSA exclusive），完全绕开 PipeWire 重采样
- 采样率自动跟随（44.1k / 96k / 192k / 384k）
- 读 /proc/asound hw_params 显示**真实**链路，不靠猜
- 频谱砖墙音质检测、64 段实时频谱
- 专辑 / 搜索 / 封面 / 歌词音乐库
- KDE Plasma 桌面组件

> AUR 包已准备完毕，但 Arch 官方暂停新账号注册（2026-06-15 起），
> 恢复后即可 `paru -S hifi4linux`。
EOF
)
```

或者在网页上建：<https://github.com/Brucelvwenhe/hifi4linux/releases/new>
选 tag `v1.0.0`，标题与说明填上面内容。

### 4.2 让仓库更容易被搜到

GitHub 的搜索权重看这几个字段（目前已填好描述与 topics，可再补）：

- **About → Description**：已填 ✅
- **About → Topics**：已填 12 个（`bit-perfect`、`alsa`、`hifi`、`kde-plasma` 等）✅
- **About → Website**：还是空的。填上仓库或文档地址，会增加可信度
- **Releases**：0 个 → 建了 v1.0.0 就有了 ⬜

### 4.3 值得投递的几个地方（都不需要审核账号）

AUR 关闭不代表没地方曝光。这些都是"发个帖/提个 PR"级别的成本：

| 渠道 | 做法 | 适合度 |
|---|---|---|
| [r/linuxaudio](https://reddit.com/r/linuxaudio)、[r/archlinux](https://reddit.com/r/archlinux) | 发一篇"我做了个 Linux bit-perfect 播放器"的帖子 | 高 —— 正好是你的目标用户 |
| [ArchWiki: Music players](https://wiki.archlinux.org/title/List_of_applications/Multimedia#Audio_players) | 你的软件符合收录条件即可加一行 | 高 —— 长期免费曝光 |
| [linuxaudio.org](https://linuxaudio.org/) 邮件列表 | 介绍项目 | 中 |
| [Awesome-Linux-Audio](https://github.com/awesome-linux-audio) 类清单 | 提 PR 加一行 | 中 |
| [HiFi 论坛 / 耳机大家坛](https://www.erji.net/) 等中文社区 | 中文用户基数大且对 bit-perfect 敏感 | 高（你是中文项目） |

> **注意**：ArchWiki 收录第三方软件有门槛（通常要求已在 AUR 或有独立条目）。
> AUR 恢复后再投 Wiki 更稳。

### 4.4 本地安装已经是一条完整路径

别忘了：`./install.sh --deps` 会自动装依赖、装到 `~/.local`、装 Plasma 组件，
**已经是"一键安装"**。它和 AUR 版的唯一差别是：

- 需要先 `git clone`（AUR 是 `paru -S`）
- 升级要 `git pull` 重跑（AUR 随 `paru -Syu`）

对绝大多数用户来说，这个差别可以忽略 —— 所以**不要把发布卡在 AUR 上**。

---

## 四、发布后建议补的（提升被发现率）

AUR 包本身不会带来流量，流量靠 README。建议在 README 顶部加：

```markdown
## 安装

[![AUR](https://img.shields.io/aur/version/hifi4linux)](https://aur.archlinux.org/packages/hifi4linux)

Arch / CachyOS / EndeavourOS / Manjaro：
```bash
paru -S hifi4linux      # 或 yay -S hifi4linux
```

其它发行版：见下方「安装」章节（install.sh）
```

另外可以去 <https://aur.archlinux.org/packages/hifi4linux> 点自己的 **Vote**，
并在 GitHub Release 里写上 AUR 安装方式。

---

## 五、以后每次发新版怎么做

假设要发 1.1.0：

```bash
cd ~/Projects/hifi4linux
# 1) 改 PKGBUILD 里的 pkgver
sed -i 's/^pkgver=.*/pkgver=1.1.0/' PKGBUILD

# 2) 提交并打新 tag（tag 必须与 pkgver 一致）
git add -A && git commit -m "v1.1.0"
git tag -a v1.1.0 -m "hifi4linux v1.1.0"
git push origin main --tags

# 3) 重新生成 .SRCINFO —— 这一步不能忘，否则 AUR 显示的还是旧版本
makepkg --printsrcinfo > .SRCINFO

# 4) 推到 AUR
cp PKGBUILD .SRCINFO /tmp/aur-hifi4linux/
cd /tmp/aur-hifi4linux
git add -A && git commit -m "hifi4linux 1.1.0-1"
git push
```

**注意 `pkgrel`**：改了打包方式但软件版本没变时（比如只修了依赖声明），
要把 `pkgrel` 从 `1` 加到 `2`，用户才会收到升级。

---

## 六、风险与常见坑

| 坑 | 说明 | 现在是否已规避 |
|---|---|---|
| `.SRCINFO` 忘记更新 | AUR 页面显示旧版本，paru 拉不到新版 | CI 已加断言：`.SRCINFO` 与 `PKGBUILD` 不一致会让 CI 失败 |
| 依赖漏声明 | 用户装完启动报错，直接卸载 | 已按脚本实际调用的命令核对补全 |
| 路径硬编码 | 装到系统路径却去找 `~/.local`，装了没用 | 已修复并实测 |
| 本地与包混装 | 用户既跑过 `install.sh` 又装了包，两份文件互相干扰 | 见下方说明 |
| 包名被占 | 极小概率 `hifi4linux` 已被注册 | 去 AUR 搜一下确认 |

### 关于本地安装与系统包共存（**重要**）

`install.sh` 装到 `~/.local`，AUR 包装到 `/usr`。两者同时存在时：

- `$PATH` 里 `~/.local/bin` 通常优先，**实际执行的是本地那份**
- `pacman -Q` 显示已装，但你跑的不是包里的文件 → 极难排查

我在打包时已经把包内脚本的探测范围**收窄到包内的 `/usr` 路径**，
所以包版本永远跑系统文件，不会去读 `~/.local` 的旧副本。但反过来，
本地那份仍会抢在 `$PATH` 前面。所以：

> **装了 AUR 包之后，请执行一次 `./uninstall.sh` 清掉 `~/.local` 的旧副本。**

`uninstall.sh` 只删 `~/.local` 下的文件，不会碰 `/usr`，两者互不干扰。

---

## 七、一句话总结

**收益**：把安装从"4 步手动"变成"1 条命令"，并让 Arch 系用户能搜到你 ——
对一个 Linux 桌面音频项目来说，这是性价比最高的一次分发动作。

**成本**：一次性 6 步操作（约 15 分钟），之后每次发版 4 条命令。

**已经做完的**：PKGBUILD、.SRCINFO、CI、tag，以及 4 个会让包"装了没用"的缺陷修复。
