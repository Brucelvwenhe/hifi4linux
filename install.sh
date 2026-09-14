#!/usr/bin/env bash
# ============================================================
#  hifi4linux —— 一键安装脚本
#
#  做三件事：
#    1. 检查（可选安装）依赖
#    2. 把程序装到 ~/.local
#    3. 可选安装 KDE Plasma 桌面组件
#
#  用法:
#    ./install.sh              安装
#    ./install.sh --no-plasma  不装 Plasma 桌面组件（非 KDE 桌面用）
#    ./install.sh --deps       顺带用包管理器装缺失的依赖
# ============================================================
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
QMLDIR="$HOME/.local/share/musicplayer"
PLASMA="$HOME/.local/share/plasma/plasmoids"

WITH_PLASMA=1
WITH_DEPS=0
for a in "$@"; do
    case "$a" in
        --no-plasma) WITH_PLASMA=0 ;;
        --deps)      WITH_DEPS=1 ;;
        -h|--help)   sed -n '2,14p' "$0"; exit 0 ;;
    esac
done

say()  { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 1. 依赖 ----------
say "检查依赖"
NEED_CMD=(mpv ffmpeg ffprobe curl python3)
NEED_PKG_ARCH=(mpv ffmpeg python qt6-declarative libpipewire pulseaudio-utils)
NEED_PKG_DEB=(mpv ffmpeg python3 qml6-module-qtquick-controls pulseaudio-utils)
MISSING=()
for c in "${NEED_CMD[@]}"; do
    command -v "$c" >/dev/null 2>&1 || MISSING+=("$c")
done
# QML 运行时
command -v qml6 >/dev/null 2>&1 || command -v qml >/dev/null 2>&1 || MISSING+=("qml6(Qt6 QML 运行时)")
# PipeWire 或 PulseAudio
command -v pactl >/dev/null 2>&1 || MISSING+=("pactl(PipeWire/PulseAudio)")

if [ ${#MISSING[@]} -gt 0 ]; then
    warn "缺少: ${MISSING[*]}"
    if [ "$WITH_DEPS" = "1" ]; then
        if command -v pacman >/dev/null 2>&1; then
            say "用 pacman 安装依赖"
            sudo pacman -S --needed --noconfirm "${NEED_PKG_ARCH[@]}"
        elif command -v apt >/dev/null 2>&1; then
            say "用 apt 安装依赖"
            sudo apt update && sudo apt install -y "${NEED_PKG_DEB[@]}"
        else
            die "请手动安装上面列出的依赖后重跑"
        fi
    else
        warn "请先安装它们（或加 --deps 让脚本代装），例如："
        warn "  Arch/CachyOS: sudo pacman -S ${NEED_PKG_ARCH[*]}"
        warn "  Debian/Ubuntu: sudo apt install ${NEED_PKG_DEB[*]}"
        die  "依赖不全，中止"
    fi
else
    say "依赖齐全"
fi

# ---------- 2. 安装文件 ----------
say "安装到 ~/.local"
mkdir -p "$BIN" "$APPS" "$QMLDIR"
install -m755 "$SRC/bin/hifi-mode"     "$BIN/hifi-mode"
install -m755 "$SRC/bin/hifiplay"      "$BIN/hifiplay"
install -m755 "$SRC/bin/theme-opacity" "$BIN/theme-opacity"
install -m755 "$SRC/bin/musicplayer"   "$BIN/musicplayer"
install -m755 "$SRC/bin/musicd.py"     "$BIN/musicd.py"
install -m644 "$SRC/qml/main.qml"      "$QMLDIR/main.qml"

# desktop 文件：把占位符换成真实路径
for f in musicplayer hifiplay; do
    sed -e "s|__PLAYER_BIN__|$BIN/musicplayer|g" \
        -e "s|__HIFIPLAY_BIN__|$BIN/hifiplay|g" \
        "$SRC/desktop/$f.desktop" > "$APPS/$f.desktop"
    chmod 644 "$APPS/$f.desktop"
done

# ---------- 3. Plasma 桌面组件（可选） ----------
if [ "$WITH_PLASMA" = "1" ] && [ -d "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
    say "安装 KDE Plasma 桌面组件"
    mkdir -p "$PLASMA/org.kde.plasma.hifimode/contents/ui"
    sed -e "s|__HIFI_BIN__|$BIN/hifi-mode|g" \
        -e "s|__PLAYER_BIN__|$BIN/musicplayer|g" \
        "$SRC/plasma/org.kde.plasma.hifimode/contents/ui/main.qml" \
        > "$PLASMA/org.kde.plasma.hifimode/contents/ui/main.qml"
    cp "$SRC/plasma/org.kde.plasma.hifimode/metadata.json" \
       "$PLASMA/org.kde.plasma.hifimode/metadata.json"
    rm -rf "$HOME/.cache/plasmashell" "$HOME/.cache/qmlcache" 2>/dev/null || true
    warn "组件已安装。重载 Plasma：systemctl --user restart plasma-plasmashell"
    warn "然后右键桌面 → 添加组件 → 搜「HiFi」加上去"
else
    [ "$WITH_PLASMA" = "1" ] && warn "未检测到 Plasma，跳过桌面组件（可用 --no-plasma 静默跳过）"
fi

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true

# ---------- 4. 曲库 ----------
if [ ! -d "$HOME/音乐" ] && [ ! -d "$HOME/Music" ]; then
    mkdir -p "$HOME/音乐"
    warn "已创建 ~/音乐 —— 把音乐放进去，或设 HIFI_MUSIC_DIRS=/路径1:/路径2"
fi
[ -f "$HOME/.cache/musicd/library.json" ] || true

cat <<EOF

$(printf '\033[1;32m安装完成\033[0m')

  启动播放器    : musicplayer          （应用菜单里搜「音乐库」）
  命令行直出播放: hifiplay 歌曲.flac
  查看直出状态  : hifi-mode status
  音质检测      : musicplayer 里点「检测音质」

  首次启动会扫描曲库（ffprobe 读标签），333 首约需 1 分钟，之后走缓存。

  提示: 若 ~/.local/bin 不在 PATH 里，请加进 shell 配置。
EOF
