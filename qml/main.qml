// ============================================================
//  音乐库播放器 —— 前端界面
//  风格与桌面一致：直角 · 半透明 · HarmonyOS Sans · 淡紫强调色
//  后端：musicd.py (127.0.0.1:8787)
// ============================================================
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: win
    visible: true
    width: 1180
    height: 720
    minimumWidth: 900
    minimumHeight: 560
    title: "音乐库"
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    // ---------- 主题（与桌面一致） ----------
    readonly property color cBg:     Qt.rgba(18 / 255, 16 / 255, 28 / 255, 0.62)
    readonly property color cPanel:  Qt.rgba(1, 1, 1, 0.045)
    readonly property color cCard:   Qt.rgba(1, 1, 1, 0.07)
    readonly property color cCardHi: Qt.rgba(1, 1, 1, 0.14)
    readonly property color cLine:   Qt.rgba(1, 1, 1, 0.10)
    readonly property color cFg:     "#ece9f7"
    readonly property color cMuted:  "#a49dc4"
    readonly property color cAccent: "#c4b5fd"
    readonly property color cGood:   "#a6e3a1"
    readonly property color cWarn:   "#f9e2af"
    readonly property string fUI:  "HarmonyOS Sans SC"
    readonly property string fNum: "Inter"

    readonly property string api: "http://127.0.0.1:8787"

    // ---------- 数据状态 ----------
    property var albums: []
    property var trackList: []        // 当前显示的曲目（专辑或搜索）
    property string listTitle: "全部曲目"
    property int curIdx: -1
    property int curAlbum: -1
    property bool playing: false
    property bool paused: true
    property real pos: 0
    property real dur: 0
    property int vol: 100
    property string nTitle: ""
    property string nArtist: ""
    property string nAlbum: ""
    property string nCodec: ""
    property int nRate: 0
    property string nBits: ""
    property bool nLossless: false
    property bool hifi: false
    property string hifiSrc: ""
    property string hifiLink: ""
    property bool hifiBP: false
    property string hifiDac: ""
    property var lyrics: []
    property int lyricIdx: -1
    property string searchText: ""
    property real bgOpacity: 0.85
    property var spectrum: []
    property var quality: null
    property bool analyzing: false

    // ---------- HTTP ----------
    function apiGet(path, cb) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE) {
                if (x.status === 200 && cb) {
                    try { cb(JSON.parse(x.responseText)); }
                    catch (e) { console.log("musicd 解析失败: " + e); }
                }
            }
        };
        x.open("GET", win.api + path);
        x.send();
    }

    function fmtTime(s) {
        s = Math.max(0, Math.floor(s || 0));
        var m = Math.floor(s / 60);
        var r = s % 60;
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    function loadLibrary() {
        apiGet("/library", function (d) {
            win.albums = d.albums || [];
            win.trackList = d.tracks || [];
            win.listTitle = "全部曲目 · " + (d.count || 0) + " 首";
        });
    }

    function showAlbum(ai) {
        win.curAlbum = ai;
        if (ai < 0) { loadLibrary(); return; }
        var alb = win.albums[ai];
        win.listTitle = alb.album + " · " + alb.artist;
        win.trackList = alb.tracks.map(function (i) { return { i: i }; });
        // 补全曲目信息
        var all = [];
        win.trackList.forEach(function (o) { all.push(o); });
        win.apiGet("/library", function (d) {
            var full = d.tracks;
            win.trackList = alb.tracks.map(function (i) { return full[i]; });
        });
    }

    function doSearch(t) {
        win.searchText = t;
        if (!t) { showAlbum(-1); return; }
        apiGet("/search?q=" + encodeURIComponent(t), function (d) {
            win.trackList = d.tracks || [];
            win.listTitle = "搜索「" + t + "」· " + (d.total || 0) + " 首";
            win.curAlbum = -2;
        });
    }

    function playIdx(i) { apiGet("/play?i=" + i, function () { pollSoon(); }); }
    function toggle()   { apiGet("/toggle", function () { pollSoon(); }); }
    function next()     { apiGet("/next", function () { pollSoon(); }); }
    function prev()     { apiGet("/prev", function () { pollSoon(); }); }
    function seek(t)    { apiGet("/seek?t=" + t, function () { pollSoon(); }); }
    function setVol(v)  { win.vol = v; apiGet("/volume?v=" + v); }
    function setHifi(on){ apiGet("/hifi?on=" + (on ? 1 : 0), function () { pollSoon(); }); }
    function setOpacity(v){ win.bgOpacity = v; apiGet("/config?opacity=" + v.toFixed(2)); }
    function loadConfig(){ apiGet("/config", function (d) { if (d.opacity) win.bgOpacity = d.opacity; }); }
    function pollSpectrum() {
        if (!win.playing || win.paused) {
            if (win.spectrum.length) win.spectrum = [];
            return;
        }
        apiGet("/spectrum", function (d) { win.spectrum = d.vals || []; });
    }
    function checkQuality() {
        if (win.curIdx < 0 || win.analyzing) return;
        win.analyzing = true;
        win.quality = null;
        apiGet("/quality?i=" + win.curIdx, function (d) {
            win.quality = d;
            win.analyzing = false;
        });
    }
    function pollSoon() { stateTimer.restart(); }
    function loadLyrics(i) {
        if (i < 0) { win.lyrics = []; win.lyricIdx = -1; return; }
        apiGet("/lyrics?i=" + i, function (d) {
            win.lyrics = d.lines || [];
            win.lyricIdx = -1;
        });
    }

    function pollState() {
        apiGet("/state", function (s) {
            win.playing = s.playing; win.paused = s.paused;
            win.pos = s.pos; win.dur = s.dur; win.vol = s.vol;
            win.nTitle = s.title; win.nArtist = s.artist; win.nAlbum = s.album;
            win.nCodec = s.codec; win.nRate = s.rate; win.nBits = s.bits;
            win.nLossless = s.lossless;
            win.hifi = s.hifi; win.hifiSrc = s.hifi_src_rate;
            win.hifiLink = s.hifi_link_rate; win.hifiBP = s.hifi_bitperfect;
            win.hifiDac = s.hifi_dac;
            if (s.idx !== win.curIdx) {
                win.curIdx = s.idx;
                loadLyrics(s.idx);
                win.quality = null;      // 换歌清空上次的音质检测结果
                win.analyzing = false;
                if (s.idx >= 0) {
                    apiGet("/quality?i=" + s.idx + "&cached=1", function (d) {
                        if (d && d.ok) win.quality = d;
                    });
                }
            }
            // 歌词高亮
            var li = -1;
            for (var k = 0; k < win.lyrics.length; k++) {
                if (win.lyrics[k].t <= win.pos + 0.25) li = k; else break;
            }
            if (li !== win.lyricIdx) {
                win.lyricIdx = li;
                lyricView.positionViewAtIndex(Math.max(0, li), ListView.Contain)
            }
        });
    }

    Timer { id: stateTimer; interval: 500; running: true; repeat: true; triggeredOnStart: true; onTriggered: pollState() }
    Timer { id: specTimer; interval: 90; running: win.playing && !win.paused; repeat: true; onTriggered: pollSpectrum() }
    Component.onCompleted: { loadLibrary(); loadConfig(); }

    // ---------- 半透明底板（透明度可调） ----------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(18 / 255, 16 / 255, 28 / 255, win.bgOpacity)
        border.width: 1
        border.color: win.cLine
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ============ 自绘标题栏 ============
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            color: "transparent"
            border.width: 0

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: win.startSystemMove()
                onDoubleClicked: win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 8
                Text { text: "\u266B"; color: win.cAccent; font.pixelSize: 17 }
                Text {
                    text: "音乐库"
                    color: win.cFg; font.family: win.fUI; font.pixelSize: 14; font.bold: true
                }
                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: 240; implicitHeight: 26
                    color: win.cPanel
                    border.width: 1; border.color: win.cLine
                    TextInput {
                        id: searchBox
                        anchors.fill: parent
                        anchors.leftMargin: 9; anchors.rightMargin: 9
                        verticalAlignment: TextInput.AlignVCenter
                        color: win.cFg; font.family: win.fUI; font.pixelSize: 12
                        selectByMouse: true
                        clip: true
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "搜索歌曲 / 艺术家 / 专辑…"
                            color: win.cMuted; font.family: win.fUI; font.pixelSize: 12
                            visible: searchBox.text === ""
                        }
                        onTextChanged: searchTimer.restart()
                    }
                    Timer { id: searchTimer; interval: 350; onTriggered: win.doSearch(searchBox.text) }
                }

                // 窗口按钮
                Repeater {
                    model: [{ g: "\u2013", a: "min" }, { g: "\u25A1", a: "max" }, { g: "\u2715", a: "close" }]
                    delegate: Rectangle {
                        required property var modelData
                        implicitWidth: 28; implicitHeight: 26
                        color: btnMa.containsMouse
                               ? (modelData.a === "close" ? "#c0392b" : win.cCardHi)
                               : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.g
                            color: win.cFg; font.pixelSize: 12
                        }
                        MouseArea {
                            id: btnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.a === "min") win.showMinimized()
                                else if (modelData.a === "max") win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized()
                                else win.close()
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: win.cLine }

        // ============ 主体三栏 ============
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ---------- 左：专辑 ----------
            ColumnLayout {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                spacing: 0

                Text {
                    Layout.leftMargin: 14; Layout.topMargin: 12; Layout.bottomMargin: 6
                    text: "专辑"
                    color: win.cMuted; font.family: win.fUI; font.pixelSize: 11; font.bold: true
                }
                ListView {
                    id: albumView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: [{ album: "全部曲目", artist: "", tracks: [] }].concat(win.albums)
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: albumView.width
                        height: 40
                        color: (win.curAlbum === index - 1)
                               ? win.cCardHi
                               : (aMa.containsMouse ? win.cPanel : "transparent")
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left; anchors.leftMargin: 14
                            anchors.right: parent.right; anchors.rightMargin: 10
                            spacing: 1
                            Text {
                                width: parent.width
                                text: modelData.album
                                color: win.cFg; font.family: win.fUI; font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: modelData.artist !== ""
                                      ? modelData.artist + " · " + (modelData.tracks ? modelData.tracks.length : 0) + " 首"
                                      : win.albums.length + " 张专辑"
                                color: win.cMuted; font.family: win.fUI; font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            id: aMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: win.showAlbum(index - 1)
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            }

            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: win.cLine }

            // ---------- 中：正在播放 ----------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 236
                    Layout.topMargin: 12

                    Rectangle {
                        id: artBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        width: 208; height: 208
                        color: win.cPanel
                        border.width: 1; border.color: win.cLine
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            // 不要加时间戳参数：那会让图片每秒重新加载 → 封面闪烁
                            // URL 只随曲目变化，QML 自己会缓存
                            source: win.curIdx >= 0 ? (win.api + "/art?i=" + win.curIdx) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: win.curIdx < 0
                            text: "\u266B"
                            color: win.cMuted; font.pixelSize: 56
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22; Layout.rightMargin: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: win.nTitle !== "" ? win.nTitle : "未在播放"
                    color: win.cFg; font.family: win.fUI; font.pixelSize: 19; font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22; Layout.rightMargin: 22
                    Layout.topMargin: 3
                    horizontalAlignment: Text.AlignHCenter
                    text: win.nArtist + (win.nAlbum !== "" ? "  ·  " + win.nAlbum : "")
                    color: win.cMuted; font.family: win.fUI; font.pixelSize: 12
                    elide: Text.ElideRight
                }
                // 格式信息（这就是你之前要的采样率/位深）
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 5
                    horizontalAlignment: Text.AlignHCenter
                    text: win.nCodec !== ""
                          ? win.nCodec + "  ·  " + win.nRate + " Hz  ·  " + (win.nBits !== "" ? win.nBits + " bit" : "—")
                            + (win.nLossless ? "  ·  无损" : "  ·  有损")
                          : ""
                    color: win.nLossless ? win.cGood : win.cWarn
                    font.family: win.fNum; font.pixelSize: 11
                }

                // ---- 音质检测（真无损 / 有损转码）----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22; Layout.rightMargin: 22
                    Layout.topMargin: 6
                    spacing: 8

                    Rectangle {
                        implicitWidth: 76; implicitHeight: 24
                        color: win.analyzing ? win.cCard : win.cCardHi
                        border.width: 1; border.color: win.cLine
                        Text {
                            anchors.centerIn: parent
                            text: win.analyzing ? "检测中…" : "检测音质"
                            color: win.analyzing ? win.cMuted : win.cAccent
                            font.family: win.fUI; font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: !win.analyzing && win.curIdx >= 0
                            onClicked: win.checkQuality()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (win.analyzing) return "正在分析频响（约 30 秒）…";
                            if (!win.quality) return "点左侧按钮，用频谱检测是否为真无损";
                            if (!win.quality.ok) return "检测失败";
                            return win.quality.verdict
                                   + "   实测上限 " + win.quality.cutoff + " kHz / 理论 " + win.quality.nyquist + " kHz";
                        }
                        color: {
                            if (win.analyzing || !win.quality || !win.quality.ok) return win.cMuted;
                            return win.quality.level === "good" ? win.cGood
                                 : (win.quality.level === "bad" ? "#f38ba8" : win.cWarn);
                        }
                        font.family: win.fUI; font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                // ---- 频谱分析仪 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22; Layout.rightMargin: 22
                    Layout.topMargin: 8
                    Layout.preferredHeight: 58
                    color: Qt.rgba(1, 1, 1, 0.03)
                    border.width: 1; border.color: win.cLine
                    clip: true

                    Row {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 1
                        Repeater {
                            model: Math.max(1, win.spectrum.length)
                            delegate: Item {
                                required property int index
                                width: (parent.width - (win.spectrum.length - 1)) / Math.max(1, win.spectrum.length)
                                height: parent.height
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: {
                                        var v = (index < win.spectrum.length) ? win.spectrum[index] : 0;
                                        return Math.max(1, parent.height * Math.min(1, v));
                                    }
                                    color: {
                                        var v = (index < win.spectrum.length) ? win.spectrum[index] : 0;
                                        if (v > 0.82) return "#f38ba8";
                                        if (v > 0.6) return win.cAccent;
                                        return Qt.rgba(196 / 255, 181 / 255, 253 / 255, 0.55);
                                    }
                                    Behavior on height { NumberAnimation { duration: 70 } }
                                }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: win.spectrum.length === 0
                        text: "频谱（播放时显示）"
                        color: win.cMuted; font.family: win.fUI; font.pixelSize: 10
                    }
                }

                Item { Layout.fillHeight: true }

                // 进度条
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22; Layout.rightMargin: 22
                    spacing: 10
                    Text {
                        text: win.fmtTime(win.pos)
                        color: win.cMuted; font.family: win.fNum; font.pixelSize: 11
                    }
                    Binding {
                        target: seekBar
                        property: "value"
                        value: win.pos
                        when: !seekBar.pressed
                        restoreMode: Binding.RestoreNone
                    }
                    Slider {
                        id: seekBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        from: 0; to: Math.max(1, win.dur)
                        // 松手才 seek；拖动过程中不被轮询覆盖（Binding 见下方）
                        onPressedChanged: {
                            if (!pressed) win.seek(value);
                        }
                        background: Rectangle {
                            x: seekBar.leftPadding
                            y: seekBar.topPadding + seekBar.availableHeight / 2 - height / 2
                            width: seekBar.availableWidth; height: 4
                            color: Qt.rgba(1, 1, 1, 0.14)
                            Rectangle {
                                width: seekBar.visualPosition * parent.width
                                height: parent.height; color: win.cAccent
                            }
                        }
                        handle: Rectangle {
                            x: seekBar.leftPadding + seekBar.visualPosition * (seekBar.availableWidth - width)
                            y: seekBar.topPadding + seekBar.availableHeight / 2 - height / 2
                            width: 12; height: 12; color: "#ffffff"
                        }
                    }
                    Text {
                        text: win.fmtTime(win.dur)
                        color: win.cMuted; font.family: win.fNum; font.pixelSize: 11
                    }
                }

                // 传输控制
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    spacing: 6
                    Repeater {
                        model: [
                            { g: "\u23EE", a: "prev", big: false },
                            { g: win.paused ? "\u25B6" : "\u23F8", a: "toggle", big: true },
                            { g: "\u23ED", a: "next", big: false }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: modelData.big ? 52 : 40
                            implicitHeight: modelData.big ? 52 : 40
                            color: tMa.containsMouse ? win.cCardHi : win.cCard
                            border.width: 1; border.color: win.cLine
                            Text {
                                anchors.centerIn: parent
                                text: modelData.g
                                color: win.cFg
                                font.pixelSize: modelData.big ? 22 : 16
                            }
                            MouseArea {
                                id: tMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.a === "prev") win.prev()
                                    else if (modelData.a === "next") win.next()
                                    else win.toggle()
                                }
                            }
                        }
                    }
                }

                // 音量 + HiFi 开关（与桌面组件同款逻辑）
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22; Layout.rightMargin: 22
                    Layout.topMargin: 12; Layout.bottomMargin: 14
                    spacing: 10

                    Text { text: "\uD83D\uDD0A"; color: win.cMuted; font.pixelSize: 13 }
                    Slider {
                        id: volBar
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 22
                        from: 0; to: 100
                        value: win.vol
                        onMoved: win.setVol(Math.round(value))
                        background: Rectangle {
                            x: volBar.leftPadding
                            y: volBar.topPadding + volBar.availableHeight / 2 - height / 2
                            width: volBar.availableWidth; height: 4
                            color: Qt.rgba(1, 1, 1, 0.14)
                            Rectangle {
                                width: volBar.visualPosition * parent.width
                                height: parent.height; color: win.cAccent
                            }
                        }
                        handle: Rectangle {
                            x: volBar.leftPadding + volBar.visualPosition * (volBar.availableWidth - width)
                            y: volBar.topPadding + volBar.availableHeight / 2 - height / 2
                            width: 12; height: 12; color: "#ffffff"
                        }
                    }
                    Text {
                        text: win.vol + "%"
                        color: win.cMuted; font.family: win.fNum; font.pixelSize: 11
                        Layout.preferredWidth: 36
                    }

                    // ---- 窗口透明度滑块 ----
                    Text {
                        text: "\u25D0"
                        color: win.cMuted; font.pixelSize: 13
                        Layout.leftMargin: 6
                    }
                    Slider {
                        id: opaBar
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 22
                        from: 0.25; to: 1.0
                        value: win.bgOpacity
                        onMoved: win.setOpacity(value)
                        background: Rectangle {
                            x: opaBar.leftPadding
                            y: opaBar.topPadding + opaBar.availableHeight / 2 - height / 2
                            width: opaBar.availableWidth; height: 4
                            color: Qt.rgba(1, 1, 1, 0.14)
                            Rectangle {
                                width: opaBar.visualPosition * parent.width
                                height: parent.height; color: win.cAccent
                            }
                        }
                        handle: Rectangle {
                            x: opaBar.leftPadding + opaBar.visualPosition * (opaBar.availableWidth - width)
                            y: opaBar.topPadding + opaBar.availableHeight / 2 - height / 2
                            width: 12; height: 12; color: "#ffffff"
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: "窗口不透明度 " + Math.round(win.bgOpacity * 100) + "%"
                    }

                    Item { Layout.fillWidth: true }

                    // ---- HiFi 直出开关 ----
                    Rectangle {
                        implicitWidth: 210; implicitHeight: 46
                        color: win.hifi ? Qt.rgba(166 / 255, 227 / 255, 161 / 255, 0.16) : win.cCard
                        border.width: 1
                        border.color: win.hifi
                                      ? (win.hifiBP ? Qt.rgba(166 / 255, 227 / 255, 161 / 255, 0.65)
                                                    : Qt.rgba(249 / 255, 226 / 255, 175 / 255, 0.65))
                                      : win.cLine
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.setHifi(!win.hifi)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 8
                            Text {
                                text: "\u266B"
                                color: win.hifi ? (win.hifiBP ? win.cGood : win.cWarn) : win.cMuted
                                font.pixelSize: 16
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: "HiFi 直出"
                                    color: win.cFg; font.family: win.fUI; font.pixelSize: 12; font.bold: true
                                }
                                Text {
                                    text: {
                                        if (!win.hifi) return "走系统混音 · 未直出";
                                        if (win.hifiBP)
                                            return "\u2713 直出 " + win.hifiLink + " Hz · 未重采样";
                                        if (win.hifiLink !== "")
                                            return "\u26A0 重采样中 " + win.nRate + "→" + win.hifiLink + " Hz";
                                        return "等待音频流…";
                                    }
                                    color: win.hifi ? (win.hifiBP ? win.cGood : win.cWarn) : win.cMuted
                                    font.family: win.fUI; font.pixelSize: 10
                                }
                            }
                            Rectangle {
                                implicitWidth: 38; implicitHeight: 19
                                color: win.hifi ? Qt.rgba(166 / 255, 227 / 255, 161 / 255, 0.75)
                                                : Qt.rgba(1, 1, 1, 0.15)
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.20)
                                Rectangle {
                                    width: 13; height: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: win.hifi ? parent.width - width - 3 : 3
                                    color: "#ffffff"
                                    Behavior on x { NumberAnimation { duration: 150 } }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: win.cLine }

            // ---------- 右：曲目 / 歌词 ----------
            ColumnLayout {
                Layout.preferredWidth: 320
                Layout.fillHeight: true
                spacing: 0

                Text {
                    Layout.leftMargin: 14; Layout.topMargin: 12; Layout.bottomMargin: 6
                    Layout.fillWidth: true
                    text: win.listTitle
                    color: win.cMuted; font.family: win.fUI; font.pixelSize: 11; font.bold: true
                    elide: Text.ElideRight
                }
                ListView {
                    id: trackView
                    Layout.fillWidth: true
                    Layout.preferredHeight: 230
                    clip: true
                    model: win.trackList
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: trackView.width
                        height: 38
                        color: (win.curIdx === (modelData.i !== undefined ? modelData.i : index))
                               ? win.cCardHi : (tMa.containsMouse ? win.cPanel : "transparent")
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14; anchors.rightMargin: 10
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: (modelData.title || "曲目 " + (index + 1))
                                color: win.cFg; font.family: win.fUI; font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: modelData.rate !== undefined && modelData.rate > 0
                                text: modelData.rate + (modelData.bits ? "/" + modelData.bits : "")
                                color: win.cMuted; font.family: win.fNum; font.pixelSize: 9
                            }
                        }
                        MouseArea {
                            id: tMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: win.playIdx(modelData.i !== undefined ? modelData.i : index)
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: win.cLine }

                Text {
                    Layout.leftMargin: 14; Layout.topMargin: 10; Layout.bottomMargin: 4
                    text: "歌词"
                    color: win.cMuted; font.family: win.fUI; font.pixelSize: 11; font.bold: true
                }
                ListView {
                    id: lyricView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.bottomMargin: 10
                    clip: true
                    model: win.lyrics
                    spacing: 7
                    delegate: Text {
                        required property var modelData
                        required property int index
                        width: lyricView.width - 28
                        x: 14
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.text
                        color: index === win.lyricIdx ? win.cAccent : win.cMuted
                        font.family: win.fUI
                        font.pixelSize: index === win.lyricIdx ? 14 : 12
                        font.bold: index === win.lyricIdx
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: win.lyrics.length === 0
                        text: win.curIdx < 0 ? "未在播放" : "（无歌词）"
                        color: win.cMuted; font.family: win.fUI; font.pixelSize: 12
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            }
        }
    }
}
