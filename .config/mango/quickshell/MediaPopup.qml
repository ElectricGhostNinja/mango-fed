import QtQuick
import Quickshell.Services.Mpris

// Now-playing popup (right-click the Media module): album art, full
// track info, click-to-seek bar, transport buttons, and a player
// switcher when more than one MPRIS player is up. All state comes from
// the Media module (passed as `media`) so the two never disagree.
// Controls in the bar's own shapes: soft pills for previous / next, an
// accent pill for play / pause, the popup sliders' track and knob for
// seeking, the volume popup's device rows for picking a player.
Popout {
    id: root

    required property var media
    readonly property var player: media.player

    // players don't announce position while paused, so read it on open
    // (a finished video otherwise showed 0:00 of 16:23)
    onVisibleChanged: if (visible) media.pos = player?.position ?? 0

    cardWidth: 320
    cardHeight: col.implicitHeight + 2 * cardPadding

    // a pill with a glyph: soft for previous / next, accent-filled for
    // the main one (play / pause)
    component TransportButton: Rectangle {
        property string glyph
        property bool main: false
        property bool allowed: true
        signal tapped()
        width: main ? 52 : 40
        height: main ? 36 : 32
        radius: 8
        opacity: allowed ? 1 : 0.35
        color: main ? (tbMa.containsMouse && allowed ? Qt.lighter(Theme.accent, 1.15) : Theme.accent)
             : tbMa.containsMouse && allowed ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.07)
        Behavior on color { ColorAnimation { duration: 120 } }
        Txt {
            anchors.centerIn: parent
            text: parent.glyph
            color: parent.main ? Theme.bg : Theme.fg
            font.pixelSize: parent.main ? 20 : 16
        }
        MouseArea {
            id: tbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: parent.allowed ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (parent.allowed) parent.tapped()
        }
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        Row {
            width: parent.width
            spacing: 12

            Rectangle {
                id: artFrame
                width: 84
                height: 84
                radius: 8
                color: Qt.alpha(Theme.fg, 0.06)
                clip: true

                Image {
                    id: art
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
                Txt {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: "󰝚"
                    color: Qt.alpha(Theme.fg, 0.3)
                    font.pixelSize: 30
                }
            }

            Column {
                width: parent.width - artFrame.width - parent.spacing
                anchors.verticalCenter: artFrame.verticalCenter
                spacing: 3

                Txt {
                    width: parent.width
                    text: root.player?.trackTitle ?? ""
                    font.pixelSize: 13
                    font.bold: true
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
                Txt {
                    width: parent.width
                    text: root.media.artistText
                    color: Qt.alpha(Theme.fg, 0.75)
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    visible: (root.player?.trackAlbum ?? "") !== ""
                    text: root.player?.trackAlbum ?? ""
                    color: Qt.alpha(Theme.fg, 0.5)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width
                    text: root.player?.identity ?? ""
                    color: Qt.alpha(Theme.accent, 0.7)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }

        // click-to-seek; hidden for streams that report no length
        Item {
            width: parent.width
            height: 30
            visible: root.media.timed

            Txt {
                anchors.left: parent.left
                anchors.top: parent.top
                text: root.media.fmt(root.media.pos)
                color: Qt.alpha(Theme.fg, 0.6)
            }
            Txt {
                anchors.right: parent.right
                anchors.top: parent.top
                text: root.media.fmt(root.media.len)
                color: Qt.alpha(Theme.fg, 0.6)
            }

            Rectangle {
                id: seekTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                height: 4
                radius: 2
                color: Qt.alpha(Theme.fg, 0.12)

                readonly property real frac: Math.min(Math.max(root.media.pos / root.media.len, 0), 1)
                Rectangle {
                    width: seekTrack.frac * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accent
                }
                // the popup sliders' knob
                Rectangle {
                    x: seekTrack.frac * parent.width - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    radius: 6
                    color: Theme.fg
                    border.width: 2
                    border.color: Theme.bg
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.topMargin: 10
                enabled: root.player?.canSeek ?? false
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: m => {
                    const frac = Math.min(Math.max(m.x / width, 0), 1)
                    root.player.position = frac * root.media.len
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰒮"
                allowed: root.player?.canGoPrevious ?? false
                onTapped: root.player.previous()
            }
            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                main: true
                glyph: root.media.playing ? "󰏤" : "󰐊"
                allowed: root.player?.canTogglePlaying ?? false
                onTapped: root.player.togglePlaying()
            }
            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰒭"
                allowed: root.player?.canGoNext ?? false
                onTapped: root.player.next()
            }
        }

        // other players, only when there's a choice to make
        Repeater {
            model: Mpris.players.values.length > 1 ? Mpris.players.values : []

            Rectangle {
                id: pRow
                required property var modelData
                readonly property bool current: modelData === root.player

                width: col.width
                height: 32
                radius: 8
                color: current ? Qt.alpha(Theme.accent, 0.18)
                     : pMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Txt {
                    id: pGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    width: 16
                    horizontalAlignment: Text.AlignHCenter
                    text: pRow.current ? "󰄬"
                        : pRow.modelData.playbackState === MprisPlaybackState.Playing ? "󰐊" : "󰏤"
                    color: pRow.current ? Theme.accent : Theme.cyan
                    font.pixelSize: 14
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: pGlyph.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    text: pRow.modelData.identity
                    elide: Text.ElideRight
                    color: pRow.current ? Theme.fg : Qt.alpha(Theme.fg, 0.9)
                    font.pixelSize: 12
                    font.bold: pRow.current
                }
                MouseArea {
                    id: pMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.media.manual = pRow.modelData
                }
            }
        }
    }
}
