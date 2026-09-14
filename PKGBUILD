# Maintainer: brucelvwenhe
pkgname=hifi4linux
pkgver=1.0.0
pkgrel=1
pkgdesc="Bit-perfect HiFi music player for Linux with a modern QML interface and KDE Plasma widget"
arch=('any')
url="https://github.com/brucelvwenhe/hifi4linux"
license=('MIT')
depends=('mpv' 'ffmpeg' 'python' 'qt6-declarative' 'libpipewire' 'pulseaudio-utils' 'wireplumber')
optdepends=('plasma-workspace: KDE 桌面组件')
source=("$pkgname-$pkgver.tar.gz")
sha256sums=('SKIP')

package() {
    install -Dm755 bin/hifi-mode      "$pkgdir/usr/bin/hifi-mode"
    install -Dm755 bin/hifiplay       "$pkgdir/usr/bin/hifiplay"
    install -Dm755 bin/theme-opacity  "$pkgdir/usr/bin/theme-opacity"
    install -Dm755 bin/musicplayer    "$pkgdir/usr/bin/musicplayer"
    install -Dm755 bin/musicd.py      "$pkgdir/usr/lib/hifi4linux/musicd.py"
    install -Dm644 qml/main.qml       "$pkgdir/usr/share/hifi4linux/main.qml"

    for f in musicplayer hifiplay; do
        sed -e "s|__PLAYER_BIN__|/usr/bin/musicplayer|g" \
            -e "s|__HIFIPLAY_BIN__|/usr/bin/hifiplay|g" \
            desktop/$f.desktop > "$pkgdir/usr/share/applications/$f.desktop"
    done

    install -d "$pkgdir/usr/share/plasma/plasmoids/org.kde.plasma.hifimode/contents/ui"
    sed -e "s|__HIFI_BIN__|/usr/bin/hifi-mode|g" \
        -e "s|__PLAYER_BIN__|/usr/bin/musicplayer|g" \
        plasma/org.kde.plasma.hifimode/contents/ui/main.qml \
        > "$pkgdir/usr/share/plasma/plasmoids/org.kde.plasma.hifimode/contents/ui/main.qml"
    install -Dm644 plasma/org.kde.plasma.hifimode/metadata.json \
        "$pkgdir/usr/share/plasma/plasmoids/org.kde.plasma.hifimode/metadata.json"
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
    install -Dm644 LICENSE   "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
