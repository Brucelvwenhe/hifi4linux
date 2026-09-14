#!/usr/bin/env bash
# 卸载 hifi4linux
set -u
say() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
say "停止播放器"
[ -f "${XDG_RUNTIME_DIR:-/tmp}/musicd.pid" ] && kill "$(cat "${XDG_RUNTIME_DIR:-/tmp}/musicd.pid")" 2>/dev/null
pkill -f 'qml6.*musicplayer/main.qml' 2>/dev/null
say "移除文件"
rm -f  "$HOME/.local/bin/"{musicplayer,musicd.py,hifi-mode,hifiplay,theme-opacity}
rm -rf "$HOME/.local/share/musicplayer"
rm -f  "$HOME/.local/share/applications/"{musicplayer,hifiplay}.desktop
rm -rf "$HOME/.local/share/plasma/plasmoids/org.kde.plasma.hifimode"
rm -rf "$HOME/.cache/musicd"
say "完成。曲库文件和 ~/.config/musicplayer.json 保留未动。"
