import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Volume popup (right-click the Volume module), in sections:
//   header — the output you're hearing, its level, a mute pill
//   Output — volume slider; every audio output PipeWire knows, click one
//     to make it the default (headphones vs speakers vs HDMI)
//   Input — only with a microphone: its level, a live meter (runs only
//     while this is open), the microphones to pick from, a mute pill
//   Apps — only while something plays: each app's own volume
//   Mixer (pavucontrol) for the rest (routing, profiles).
// All of it straight from the Pipewire service, so changes made anywhere
// else show here too.
Popout {
    id: root
    ipcNames: ["volume"]

    cardWidth: 340
    cardHeight: col.implicitHeight + 2 * cardPadding

    // Filters use only what PipeWire announces up front (sink/stream, node
    // name): a node's audio and properties arrive after it's bound, and a
    // list that changed with them would bind, unbind and rebind forever.
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)
    // microphones only: cameras are non-stream nodes too
    readonly property var sources: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSource)
    // what apps are playing (output streams; the meter below is an input
    // stream, so it never shows), grouped by app: Firefox's four tabs are
    // one Firefox slider that moves them all
    readonly property var outStreams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream)
    readonly property var apps: {
        const groups = []
        for (const n of outStreams) {
            const name = appLabel(n)
            const g = groups.find(g => g.name === name)
            if (g) g.nodes.push(n)
            else groups.push({ name: name, nodes: [n] })
        }
        return groups
    }

    // bound so their audio state (volume, mute) stays live while listed
    PwObjectTracker { objects: root.sinks.concat(root.sources, root.outStreams) }

    readonly property var current: Pipewire.defaultAudioSink
    readonly property var audio: current?.audio ?? null
    // the default source only if it really is a microphone: with none
    // chosen, PipeWire can hand back an output here (butterbian does),
    // and "mute input" would mute the speakers
    readonly property var mic: Pipewire.defaultAudioSource?.type === PwNodeType.AudioSource
                               ? Pipewire.defaultAudioSource : null
    readonly property var micAudio: mic?.audio ?? null

    // the microphone's live level, only while the popup is open
    PwNodePeakMonitor {
        id: meter
        node: root.mic
        enabled: root.visible && root.mic !== null
    }

    function label(n) {
        return n.description || n.nickname || n.name
    }
    function appLabel(n) {
        return n.properties?.["application.name"] || n.name || "app"
    }
    function pct(a) {
        return a ? Math.round(a.volume * 100) : 0
    }

    // mute pill: soft like the bar's pills, red while muted
    component MutePill: Rectangle {
        property bool muted: false
        signal toggled()
        width: muteText.implicitWidth + 36
        height: 24
        radius: 8
        color: muted ? Theme.red
             : muteMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.07)
        Behavior on color { ColorAnimation { duration: 150 } }
        Row {
            anchors.centerIn: parent
            spacing: 6
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.muted ? "󰖁" : "󰕾"
                color: parent.parent.muted ? Theme.bg : Theme.cyan
                font.pixelSize: 13
            }
            Txt {
                id: muteText
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.muted ? "muted" : "mute"
                color: parent.parent.muted ? Theme.bg : Theme.fg
                font.bold: parent.parent.muted
            }
        }
        MouseArea {
            id: muteMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.toggled()
        }
    }

    // one device row: glyph, name; the default one highlighted
    component DeviceRow: Rectangle {
        id: dev
        required property var modelData
        property var chosen: null
        property string glyph: "󰓃"
        signal picked()
        readonly property bool active: modelData === chosen

        width: parent.width
        height: 32
        radius: 8
        color: active ? Qt.alpha(Theme.accent, 0.18)
             : devMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }

        Txt {
            id: devGlyph
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            horizontalAlignment: Text.AlignHCenter
            text: dev.active ? "󰄬" : dev.glyph
            color: dev.active ? Theme.accent : Theme.cyan
            font.pixelSize: 14
        }
        Txt {
            anchors.left: devGlyph.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.label(dev.modelData)
            elide: Text.ElideRight
            color: dev.active ? Theme.fg : Qt.alpha(Theme.fg, 0.9)
            font.pixelSize: 12
            font.bold: dev.active
        }
        MouseArea {
            id: devMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dev.picked()
        }
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        // --- header: what you're hearing ---
        Item {
            width: parent.width
            height: 48

            // the media popup's tile
            Rectangle {
                id: tile
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                radius: 8
                color: Qt.alpha(Theme.fg, 0.06)

                Txt {
                    anchors.centerIn: parent
                    text: root.audio?.muted ? "󰝟"
                        : root.pct(root.audio) < 25 ? "󰕿"
                        : root.pct(root.audio) < 65 ? "󰖀" : "󰕾"
                    color: root.audio?.muted ? Qt.alpha(Theme.fg, 0.45) : Theme.green
                    font.pixelSize: 22
                }
            }

            Column {
                anchors.left: tile.right
                anchors.leftMargin: 12
                anchors.right: outMute.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Txt {
                    text: "Volume"
                    font.pixelSize: 13
                    font.bold: true
                }
                Txt {
                    width: parent.width
                    text: (root.current ? root.label(root.current) : "no output")
                        + " · " + (root.audio?.muted ? "muted" : root.pct(root.audio) + "%")
                    color: Qt.alpha(Theme.fg, 0.55)
                    elide: Text.ElideRight
                }
            }

            MutePill {
                id: outMute
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                muted: root.audio?.muted ?? false
                onToggled: if (root.audio) root.audio.muted = !root.audio.muted
            }
        }

        // --- Output ---
        SectionLabel { text: "Output" }

        TweakSlider {
            label: "volume"
            from: 0; to: 100
            value: root.pct(root.audio)
            suffix: "%"
            applyFn: v => {
                if (!root.audio) return
                root.audio.muted = false
                root.audio.volume = v / 100
            }
            persistFn: v => {}   // PipeWire remembers
        }

        Repeater {
            model: root.sinks
            DeviceRow {
                chosen: root.current
                glyph: "󰓃"
                onPicked: Pipewire.preferredDefaultAudioSink = modelData
            }
        }

        Txt {
            visible: root.sinks.length === 0
            text: "no outputs"
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: 12
            leftPadding: 10
        }

        // --- Input: only with a microphone ---
        Item {
            visible: root.sources.length > 0
            width: parent.width
            height: 30

            SectionLabel {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                topPadding: 0
                text: "Input"
            }
            MutePill {
                visible: root.micAudio !== null
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                muted: root.micAudio?.muted ?? false
                onToggled: if (root.micAudio) root.micAudio.muted = !root.micAudio.muted
            }
        }

        TweakSlider {
            visible: root.micAudio !== null
            label: "microphone"
            from: 0; to: 100
            value: root.pct(root.micAudio)
            suffix: "%"
            applyFn: v => {
                if (!root.micAudio) return
                root.micAudio.volume = v / 100
            }
            persistFn: v => {}
        }

        // live level: square root so speech fills a useful part of the
        // bar; red near clipping
        Rectangle {
            visible: root.micAudio !== null
            width: parent.width - 8
            anchors.horizontalCenter: parent.horizontalCenter
            height: 4
            radius: 2
            color: Qt.alpha(Theme.fg, 0.1)

            Rectangle {
                readonly property real level: root.micAudio?.muted ? 0 : Math.min(1, Math.sqrt(meter.peak))
                width: parent.width * level
                height: parent.height
                radius: 2
                color: level > 0.95 ? Theme.red : Theme.accent
                Behavior on width { NumberAnimation { duration: 80 } }
            }
        }

        Repeater {
            model: root.sources
            DeviceRow {
                chosen: root.mic
                glyph: "󰍬"
                onPicked: Pipewire.preferredDefaultAudioSource = modelData
            }
        }

        // --- Apps: each thing playing, its own level ---
        SectionLabel {
            visible: root.apps.length > 0
            text: "Apps"
        }

        Repeater {
            model: root.apps

            TweakSlider {
                id: appSlider
                required property var modelData
                label: modelData.name
                from: 0; to: 100
                value: root.pct(modelData.nodes[0].audio)
                suffix: "%"
                applyFn: v => {
                    for (const n of appSlider.modelData.nodes)
                        if (n.audio) n.audio.volume = v / 100
                }
                persistFn: v => {}
            }
        }

        Rectangle {
            width: parent.width - 8
            anchors.horizontalCenter: parent.horizontalCenter
            height: 1
            color: Qt.alpha(Theme.fg, 0.15)
        }

        Rectangle {
            width: parent.width
            height: 34
            radius: 8
            color: mixMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 10
                spacing: 10

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰕾"
                    color: Theme.cyan
                    font.pixelSize: 15
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mixer (pavucontrol)"
                    color: Qt.alpha(Theme.fg, 0.9)
                    font.pixelSize: 13
                }
            }

            MouseArea {
                id: mixMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.visible = false
                    Quickshell.execDetached(["pavucontrol"])
                }
            }
        }
    }
}
