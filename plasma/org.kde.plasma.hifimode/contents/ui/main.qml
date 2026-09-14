// HiFi 直出模式 —— 桌面开关 + 实时音频指标
// 数据来源: ~/.local/bin/hifi-mode status
//   格式: state|源采样率|链路采样率|链路格式|是否直出|应用|流数|图采样率|设备
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 8

    property bool hifiOn: false
    property string srcRate: ""
    property string linkRate: ""
    property string linkSpec: ""
    property bool bitPerfect: false
    property string curApp: ""
    property string nStreams: ""
    property string dacName: ""
    property string linkBits: ""
    property string srcSpec: ""
    property string srcBits: ""

    readonly property string bin: "__HIFI_BIN__"
    readonly property string playerBin: "__PLAYER_BIN__"
    readonly property color cFg: "#ece9f7"
    readonly property color cMuted: "#a49dc4"
    readonly property color cGood: "#a6e3a1"
    readonly property color cWarn: "#f9e2af"
    readonly property color cAccent: "#c4b5fd"
    readonly property color cCard: Qt.rgba(1, 1, 1, 0.06)
    readonly property color cCardHi: Qt.rgba(1, 1, 1, 0.14)
    readonly property color cLine: Qt.rgba(1, 1, 1, 0.10)

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        onNewData: function (sourceName, data) {
            var out = ((data && data.stdout) ? data.stdout : "").trim();
            if (sourceName.indexOf("status") !== -1 && out !== "") {
                var p = out.split("|");
                root.hifiOn     = (p[0] === "on");
                root.srcRate    = (p[1] || "").trim();
                root.linkRate   = (p[2] || "").trim();
                root.linkSpec   = (p[3] || "").trim();
                root.bitPerfect = ((p[4] || "").trim() === "1");
                root.curApp     = (p[5] || "").trim();
                root.nStreams   = (p[6] || "").trim();
                root.dacName    = (p[8] || "").trim();
                root.linkBits   = (p[9] || "").trim();
                root.srcSpec    = (p[10] || "").trim();
                root.srcBits    = (p[11] || "").trim();
            }
            exec.disconnectSource(sourceName);
        }
    }

    function refresh() { exec.connectSource(root.bin + " status"); }
    // 启动音乐库播放器。必须用 connectSource —— 组件里只有这一条通路
    // 是确定能跑起来的（之前的 run() 是个不存在的函数，所以点了没反应）
    function launch()  { exec.connectSource(root.bin + " player"); }
    function toggle()  { exec.connectSource(root.bin + " toggle"); afterTimer.restart(); }

    Timer { id: afterTimer; interval: 1200; repeat: false; onTriggered: root.refresh() }
    Timer {
        interval: 2500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    fullRepresentation: Item {
        // 桌面组件不在 Layout 中，必须给 implicitWidth/Height 才有尺寸
        implicitWidth: Kirigami.Units.gridUnit * 13
        implicitHeight: Kirigami.Units.gridUnit * 11
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: Kirigami.Units.gridUnit * 10
        Layout.minimumHeight: Kirigami.Units.gridUnit * 6
        width: implicitWidth
        height: implicitHeight

        Rectangle {
            id: card
            anchors.fill: parent
            color: Qt.rgba(18 / 255, 16 / 255, 28 / 255, 0.55)
            border.width: 1
            border.color: root.hifiOn
                          ? (root.bitPerfect ? Qt.rgba(166 / 255, 227 / 255, 161 / 255, 0.65)
                                             : Qt.rgba(249 / 255, 226 / 255, 175 / 255, 0.65))
                          : Qt.rgba(1, 1, 1, 0.10)

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: root.toggle()
                z: -1
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 5

                // ---------- 标题行 + 自绘开关 ----------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "\u266B"
                        color: root.hifiOn ? (root.bitPerfect ? root.cGood : root.cWarn) : root.cMuted
                        font.pixelSize: 17
                    }
                    Text {
                        text: "HiFi 直出"
                        color: root.cFg
                        font.pixelSize: 14
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    // 自绘开关（不依赖 PlasmaComponents）
                    Rectangle {
                        id: knobTrack
                        implicitWidth: 40
                        implicitHeight: 20
                        color: root.hifiOn ? Qt.rgba(166 / 255, 227 / 255, 161 / 255, 0.75)
                                           : Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.20)

                        Rectangle {
                            id: knob
                            width: 14; height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.hifiOn ? parent.width - width - 3 : 3
                            color: "#ffffff"
                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggle()
                        }
                    }
                }

                // ---------- 关闭状态 ----------
                Text {
                    Layout.fillWidth: true
                    visible: !root.hifiOn
                    text: "共享输出 · 自动重采样"
                    color: root.cMuted
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    visible: !root.hifiOn
                    text: "打开后只从 USB DAC 出声"
                    color: root.cMuted
                    font.pixelSize: 10
                }

                // ---------- 底部：进入音乐库播放器 ----------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 5
                    implicitHeight: 26
                    color: openMa.containsMouse ? root.cCardHi : root.cCard
                    border.width: 1
                    border.color: root.cLine

                    Text {
                        anchors.centerIn: parent
                        text: "\u266B  打开音乐库  \u203A"
                        color: root.cAccent
                        font.family: "HarmonyOS Sans SC"
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: openMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        propagateComposedEvents: false
                        onClicked: root.launch()
                    }
                }

                // ---------- 开启状态：指标 ----------
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.hifiOn
                    spacing: 3

                    Repeater {
                        model: [
                            { k: "源采样率", v: root.srcRate !== "" ? root.srcRate + " Hz" : "无播放",
                              c: root.srcRate !== "" ? root.cFg : root.cMuted },
                            { k: "源位深", v: root.srcBits !== "" ? root.srcBits + " bit" : "—",
                              c: root.srcBits !== "" ? root.cFg : root.cMuted },
                            { k: "DAC 链路", v: root.linkRate !== "" ? root.linkRate + " Hz" : "—", c: root.cFg },
                            { k: "链路位深", v: root.linkBits !== "" ? root.linkBits + " bit 容器" : "—", c: root.cFg },
                            { k: "链路格式", v: root.linkSpec !== "" ? root.linkSpec : "—", c: root.cMuted },
                            { k: "状态",
                              v: root.srcRate === "" ? "待播放"
                                 : (root.bitPerfect
                                    ? "\u2713 直出 " + root.linkRate + " Hz（未重采样）"
                                    : "\u26A0 重采样 " + root.srcRate + "→" + root.linkRate + " Hz"),
                              c: root.srcRate === "" ? root.cMuted
                                 : (root.bitPerfect ? root.cGood : root.cWarn) },
                            { k: "播放应用", v: root.curApp !== "" ? root.curApp : "—", c: root.cMuted },
                            { k: "活动流数", v: root.nStreams !== "" ? root.nStreams + " 路" : "0 路",
                              c: root.nStreams === "1" ? root.cGood : root.cMuted }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: modelData.k
                                color: root.cMuted
                                font.pixelSize: 10
                                Layout.preferredWidth: 58
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.v
                                color: modelData.c
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
