# hifi4linux

**Linux 上的 bit-perfect（真直出）HiFi 播放器 + 现代界面**

[![Release](https://img.shields.io/github/v/release/Brucelvwenhe/hifi4linux)](https://github.com/Brucelvwenhe/hifi4linux/releases/latest)
[![License](https://img.shields.io/github/license/Brucelvwenhe/hifi4linux)](LICENSE)

直出到底有多"直"？音频从文件解码到 USB DAC，**中间不经过任何重采样** —— 是多少 Hz 就输出多少 Hz，是多少 bit 就送多少 bit。

```
源   FLAC 96000Hz / 24bit
链路 96000Hz / S32_LE          ← 直接读 ALSA 硬件参数，不是猜的
直出 ✓ 是
```

---

## 为什么需要它

网易云、QQ音乐、浏览器这些客户端都是 **Electron/Chromium 内核**，音频在客户端内部就被重采样成固定 48kHz 了 —— 交到系统时已经不是原始采样率，任何外部设置都救不回来。真正要 bit-perfect，必须用**原生解码 + 独占音频设备**的播放器。

hifi4linux 就是干这个的，而且把它做成了**日常能用的桌面软件**，不是命令行玩具。

## 功能

| 功能 | 说明 |
|---|---|
| **一键 HiFi 直出** | 独占 USB DAC（ALSA exclusive），完全绕开 PipeWire 重采样 |
| **采样率自动跟随** | 换歌自动切 DAC 硬件采样率，44.1k / 96k / 192k / 384k 都行 |
| **真实状态显示** | 读 `/proc/asound/.../hw_params` 内核参数，直出就是直出，重采样就显示 `44100→48000` |
| **音质检测** | 频谱砖墙分析（同 Spek / foobar2000），识别假无损 / 有损转码 |
| **实时频谱** | 64 段分析仪，从文件解码算，独占模式下也正常显示 |
| **音乐库界面** | 专辑分组、搜索、封面、歌词（.lrc + 内嵌）、播放控制 |
| **桌面组件** | KDE Plasma 组件：开关 + 实时指标 + 一键打开播放器 |
| **命令行直出** | `hifiplay 歌曲.flac`，右键音频文件即可 |
| **外观可调** | 播放器透明度滑块；`theme-opacity` 调整个桌面毛玻璃 |
| **设备无关** | 自动识别任意 USB DAC，换设备零配置 |

## 界面

- **主界面**：三栏布局 —— 专辑列表 / 封面+频谱+控制 / 曲目+歌词
- **风格**：直角 · 半透明毛玻璃 · 跟随系统字体与配色
- **桌面组件**：绿色=直出正常，黄色=重采样中，灰色=未开启

## 安装

### Arch / CachyOS / EndeavourOS / Manjaro

```bash
git clone https://github.com/Brucelvwenhe/hifi4linux.git
cd hifi4linux
./install.sh --deps
```

> [!NOTE]
> **AUR 包已完全准备好，但暂时无法上架。**
> Arch 官方自 2026-06-15 起因「恶意软件包事件」**暂停了新账号注册**
> （[公告](https://lists.archlinux.org/archives/list/aur-general@lists.archlinux.org/thread/4JRS73YVTE7JUYHHE3ZDUIHXYHXZ3YQQ/)），
> 没有人工队列，也不接受加急。等注册恢复后即可用
> `paru -S hifi4linux` 安装（PKGBUILD 与 .SRCINFO 已就位并通过构建验证）。
> 在那之前，请用上面的方式安装 —— 功能完全一致。
>
> 恢复时间见 [Arch 新闻](https://archlinux.org/news/)。

### Debian / Ubuntu

```bash
sudo apt install mpv ffmpeg python3 qml6-module-qtquick-controls pulseaudio-utils
git clone https://github.com/brucelvwenhe/hifi4linux.git
cd hifi4linux
./install.sh --no-plasma      # 非 KDE 桌面加这个参数
```

### 依赖

| 依赖 | 用途 |
|---|---|
| `mpv` | 音频引擎（支持 `--audio-exclusive` 独占） |
| `ffmpeg` / `ffprobe` | 格式探测、频谱分析、封面提取 |
| `python3` | 播放器后端（只用标准库，无需 pip） |
| Qt6 QML 运行时 | 图形界面 |
| PipeWire 或 PulseAudio | 共享模式下的音频路由 |
| `wireplumber`（可选） | 自动恢复设备（KDE/GNOME 一般自带） |
| KDE Plasma（可选） | 桌面组件 |

## 使用

```bash
musicplayer                 # 启动播放器（应用菜单里搜「音乐库」）
hifiplay 歌曲.flac          # 命令行 bit-perfect 播放
hifiplay --info 歌曲.flac   # 只看格式（含源文件真实位深）
hifi-mode on|off|toggle     # 开关直出模式
hifi-mode status            # 查看状态
hifi-mode metrics           # 人类可读的完整指标
hifi-mode rescue            # 出问题时一键恢复所有音频
theme-opacity 0.45          # 调整桌面毛玻璃透明度
```

曲库目录默认 `~/音乐`，可改：

```bash
export HIFI_MUSIC_DIRS="$HOME/音乐:$HOME/Music:/mnt/nas/music"
```

## 工作原理

### 直出是怎么实现的

```
普通模式:  播放器 → PipeWire 混音器(重采样到图采样率) → ALSA → DAC
HiFi 模式: 播放器 ────────── ALSA 独占 ──────────────→ DAC
```

开启直出后，mpv 用 `--ao=alsa --audio-device=alsa/hw:N,0 --audio-exclusive=yes` 直接打开硬件设备：

- **完全绕开 PipeWire** —— 没有混音、没有重采样
- **独占设备** —— 其它程序不能同时用这个 DAC（这正是"独占"的意义）
- **采样率跟着文件走** —— `--audio-samplerate` 默认 0 即"用文件原始采样率"

### 关于 24bit 显示成 32bit

不是升频，也不是 bug。很多 USB DAC（如 NICEHCK NK1 MAX）硬件**只支持 S32_LE**，24bit 样本放进 32bit 容器**低位补零，数据完全没变**。所以界面上标的是「**32 bit 容器**」。

### 关于直出判定

判定**不靠猜**，而是三个条件同时成立：

1. 读 `/proc/asound/cardN/pcm0p/sub0/hw_params` —— 硬件**真实**运行速率
2. 播放器**确实在播放**（不是挂着文件或暂停 —— 否则浏览器放视频时会误报直出）
3. 硬件速率 == 当前曲目的采样率

## 疑难排查

**切来切去之后没声音了？**

```bash
hifi-mode rescue
```

会自动：取消所有静音/挂起 → 恢复默认输出 → 必要时重启 wireplumber 重新发现 DAC → 清除强制采样率。

> 原理：独占期间 ALSA 设备被 mpv 占着，wireplumber 探测失败时会**静默地不给这个设备创建 sink**，DAC 就从 PipeWire 里整个消失了。这种情况 `suspend` 救不回来，必须重启 wireplumber。本程序在切回共享模式时会自动检测并修复。

**关掉播放器后浏览器没声音 / DAC 不见了？**

已自动处理：播放器退出时会**自动关闭直出**，取消所有声卡的静音，并把 USB DAC 交还 PipeWire。

但如果是被 `kill -9` 强杀（或断电），清理逻辑来不及跑，手动执行：

```bash
hifi-mode rescue
```

**桌面组件按钮点不开播放器？**

实现方式是调用 `hifi-mode player`，由 `systemd-run --user` 拉起进程 —— 这样它完全脱离 Plasma 数据源，不会被连带杀掉。手动等效命令：

```bash
hifi-mode player
```

**显示"重采样中 44100→48000"？**

说明播放器没在用独占模式。检查：
- 桌面组件开关是否真的打开（绿色）
- `hifi-mode status` 第一段是否为 `on`

**没有声音 / 找不到 DAC？**

```bash
aplay -l                    # 系统层面能否看到声卡
hifi-mode info              # 本程序识别到的设备
pactl list short sinks      # PipeWire 里有没有它
```

**播放器起不来？**

```bash
python3 ~/.local/bin/musicd.py    # 直接跑，看报错
```

## 已知限制

- **独占模式下同一时刻只能一个程序用 DAC** —— 这是 bit-perfect 的固有代价。想边听歌边看视频就关掉直出。
- **浏览器/网易云无法 bit-perfect** —— 客户端内核重采样，非本程序能解决。建议：网易云下载无损 → 用本播放器播。
- **DSD 原生输出**未支持（会走 DoP 或转 PCM）。
- 桌面组件目前面向 **KDE Plasma 6**。

## 项目结构

```
hifi4linux/
├── bin/
│   ├── musicd.py        # 播放器后端（曲库/播放控制/频谱/音质检测/HTTP API）
│   ├── musicplayer      # 播放器启动器
│   ├── hifi-mode        # 直出模式核心（开关、采样率跟随、设备恢复）
│   ├── hifiplay         # 命令行 bit-perfect 播放器
│   └── theme-opacity    # 桌面毛玻璃透明度调节
├── qml/main.qml         # 播放器界面
├── plasma/              # KDE Plasma 桌面组件
├── desktop/             # .desktop 桌面项
├── .github/workflows/   # CI：shellcheck / py_compile / QML / PKGBUILD 校验
├── install.sh           # 一键安装（装到 ~/.local）
├── uninstall.sh
├── PKGBUILD             # Arch 打包（装到 /usr，供 AUR）
├── .SRCINFO             # AUR 必需元数据（由 makepkg --printsrcinfo 生成）
└── PUBLISHING-AUR.md    # 发布到 AUR 的步骤与收益说明
```

## License

MIT
