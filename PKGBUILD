# Maintainer: brucelvwenhe <https://github.com/brucelvwenhe>
# AUR 包：hifi4linux
# 问题反馈：https://github.com/brucelvwenhe/hifi4linux/issues
#
# 说明：本包用 VCS(git) 源而非固定 tarball，这样打新 tag 后无需手改校验和。
#       如果以后想改成固定版本，把 source 换成：
#         "$pkgname-$pkgver.tar.gz::https://github.com/brucelvwenhe/hifi4linux/archive/refs/tags/v$pkgver.tar.gz"
#       然后用 `updpkgsums` 填入真实 sha256。

pkgname=hifi4linux
pkgver=1.0.0
pkgrel=1
pkgdesc="Bit-perfect HiFi player for Linux: exclusive USB DAC output, automatic sample-rate switching, QML UI and KDE Plasma widget"
arch=('any')
url="https://github.com/brucelvwenhe/hifi4linux"
license=('MIT')
# 运行时依赖：
#   mpv / ffmpeg(含 ffprobe)  解码与直出播放
#   python                    musicd.py 曲库扫描
#   qt6-declarative           提供 qml6 运行时（界面必需）
#   libpulse                  pactl 音量与设备接管（PipeWire 亦通过它兼容）
#   curl                      封面与歌词抓取
#   libnotify                 hifi-mode 的状态通知
# systemd 提供 systemctl，属 base 元包，通常不需要显式声明
depends=('mpv' 'ffmpeg' 'python' 'qt6-declarative' 'libpulse' 'curl' 'libnotify')
# KDE Plasma 桌面组件需要 Plasma 运行时；非 KDE 桌面可不装
optdepends=(
    'plasma-workspace: KDE Plasma 桌面组件（org.kde.plasma.* 模块）'
    'wireplumber: PipeWire 会话管理（PipeWire 用户建议安装）'
)
provides=('hifi4linux')
conflicts=('hifi4linux-git')
source=("$pkgname::git+file:///home/bruce/Projects/hifi4linux#tag=v1.0.0")
sha256sums=('SKIP')

pkgver() {
    cd "$pkgname"
    # 检出点是 tag（发布版）→ 直接用 tag 号，得到干净的 1.0.0
    # 这样版本号只由 tag 决定，不会因为分支上多了提交就自动漂移。
    local tag
    tag=$(git describe --exact-match --tags HEAD 2>/dev/null)
    if [ -n "$tag" ]; then
        printf '%s' "${tag#v}"
        return
    fi
    # 跟在某个 tag 之后（开发版）→ 1.0.0.r3.gabc1234
    local base
    base=$(git describe --tags --abbrev=0 2>/dev/null)
    if [ -n "$base" ]; then
        printf '%s.r%s.g%s' \
            "${base#v}" \
            "$(git rev-list --count "$base"..HEAD)" \
            "$(git rev-parse --short=7 HEAD)"
        return
    fi
    # 仓库里一个 tag 都没有（纯开发）
    printf '0.0.0.r%s.g%s' \
        "$(git rev-list --count HEAD)" \
        "$(git rev-parse --short=7 HEAD)"
}

package() {
    cd "$pkgname"

    # ── 可执行文件 ──────────────────────────────────────────────────────────
    install -Dm755 bin/hifi-mode      "$pkgdir/usr/bin/hifi-mode"
    install -Dm755 bin/hifiplay       "$pkgdir/usr/bin/hifiplay"
    install -Dm755 bin/theme-opacity  "$pkgdir/usr/bin/theme-opacity"
    install -Dm755 bin/musicd.py      "$pkgdir/usr/lib/hifi4linux/musicd.py"
    install -Dm644 qml/main.qml       "$pkgdir/usr/share/hifi4linux/main.qml"

    # ── musicplayer ─────────────────────────────────────────────────────────
    # 源码里是「本地优先、回退系统路径」的探测逻辑。打包时必须显式把探测范围
    # 收窄到包内路径，否则用户机器上若还留着 ~/.local 的旧副本，
    # 系统包会去跑那份旧文件（版本混装，极难排查）。
    install -Dm755 bin/musicplayer "$pkgdir/usr/bin/musicplayer"
    sed -i \
        -e 's|^for c in "\$HOME/.local/bin/musicd.py".*|for c in /usr/lib/hifi4linux/musicd.py; do|' \
        -e 's|^for c in "\$HOME/.local/share/musicplayer/main.qml".*|for c in /usr/share/hifi4linux/main.qml; do|' \
        "$pkgdir/usr/bin/musicplayer"
    # 注入后必须真的命中；源码一旦改了写法，这里立刻失败，而不是发出一个坏包
    grep -q 'for c in /usr/lib/hifi4linux/musicd.py' "$pkgdir/usr/bin/musicplayer" \
        || { echo "错误：musicplayer 后端路径注入失败" >&2; exit 1; }
    grep -q 'for c in /usr/share/hifi4linux/main.qml' "$pkgdir/usr/bin/musicplayer" \
        || { echo "错误：musicplayer 界面路径注入失败" >&2; exit 1; }

    # ── hifi-mode：同样把播放器探测范围锁定到包内路径 ───────────────────────
    sed -i \
        -e 's|^    for c in "\$HOME/.local/bin/musicplayer" /usr/bin/musicplayer; do|    for c in /usr/bin/musicplayer; do|' \
        "$pkgdir/usr/bin/hifi-mode"
    grep -q 'for c in /usr/bin/musicplayer; do' "$pkgdir/usr/bin/hifi-mode" \
        || { echo "错误：hifi-mode 播放器路径注入失败" >&2; exit 1; }

    # ── 桌面入口：把占位符替换成系统路径 ────────────────────────────────────
    # 注意：sed 的 > 重定向不会创建父目录，必须先 install -d，
    #       否则 makepkg 在这一步直接失败（本地 install.sh 没这问题，因为它自己 mkdir 过）
    install -d "$pkgdir/usr/share/applications"
    for f in musicplayer hifiplay; do
        sed -e "s|__PLAYER_BIN__|/usr/bin/musicplayer|g" \
            -e "s|__HIFIPLAY_BIN__|/usr/bin/hifiplay|g" \
            desktop/$f.desktop > "$pkgdir/usr/share/applications/$f.desktop"
        chmod 644 "$pkgdir/usr/share/applications/$f.desktop"
    done

    # ── KDE Plasma 桌面组件 ─────────────────────────────────────────────────
    install -d "$pkgdir/usr/share/plasma/plasmoids/org.kde.plasma.hifimode/contents/ui"
    sed -e "s|__HIFI_BIN__|/usr/bin/hifi-mode|g" \
        -e "s|__PLAYER_BIN__|/usr/bin/musicplayer|g" \
        plasma/org.kde.plasma.hifimode/contents/ui/main.qml \
        > "$pkgdir/usr/share/plasma/plasmoids/org.kde.plasma.hifimode/contents/ui/main.qml"
    install -Dm644 plasma/org.kde.plasma.hifimode/metadata.json \
        "$pkgdir/usr/share/plasma/plasmoids/org.kde.plasma.hifimode/metadata.json"

    # ── 文档与许可证 ────────────────────────────────────────────────────────
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 LICENSE   "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
