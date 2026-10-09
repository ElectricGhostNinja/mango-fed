import QtQuick
import Quickshell

// The command menu's quick-settings tile: glyph, name, and the current
// state underneath, so "Power profile / Balanced" says what it is AND
// where it's at. On = accent fill; alert (mic muted, DND on) = red fill,
// states you shouldn't forget. Left click runs modelData.run; right click
// modelData.altFn (a fuller tool) when there is one. modelData.adjust
// puts − / + after the state (the focus timer's length), visible instead
// of hidden behind scroll or right-click.
Rectangle {
    id: tile
    required property var modelData
    readonly property bool on: modelData.active === true
    readonly property bool alert: modelData.alert === true
    readonly property color ink: alert || on ? Theme.bg : Theme.fg

    width: (parent.width - 6) / 2
    height: 48
    radius: 8
    color: alert ? Theme.red
         : on ? Theme.accent
         : tileMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.07)

    Behavior on color { ColorAnimation { duration: 150 } }

    MouseArea {
        id: tileMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => {
            if (m.button === Qt.RightButton)
                tile.modelData.altFn?.()
            else
                tile.modelData.run()
        }
    }

    Txt {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text: tile.modelData.icon
        color: tile.alert || tile.on ? Theme.bg : Theme.cyan
        font.pixelSize: 16
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Txt {
            width: parent.width
            text: tile.modelData.name
            color: tile.ink
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
        }

        // state, then − / + for tiles that have them (the timer's length)
        Row {
            spacing: 6

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: tile.modelData.state
                color: Qt.alpha(tile.ink, 0.7)
            }

            Repeater {
                model: tile.modelData.adjust ? [-1, 1] : []

                Rectangle {
                    id: adj
                    required property int modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 4
                    color: adjMa.containsMouse ? Qt.alpha(tile.ink, 0.2) : Qt.alpha(tile.ink, 0.08)

                    Txt {
                        anchors.centerIn: parent
                        text: adj.modelData < 0 ? "−" : "+"
                        color: tile.ink
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: adjMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tile.modelData.adjust(adj.modelData)
                    }
                }
            }
        }
    }
}
