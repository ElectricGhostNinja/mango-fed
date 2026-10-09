import QtQuick
import Quickshell
import Quickshell.Io

// Power menu (Super+x, or Power menu in the command menu): screen off, log
// out, reboot, shut down. Arrows or j/k pick, Enter runs, or press the
// row's letter. The three that end the session want a second press: the
// first turns the row red, and it disarms after a few seconds. Logout goes
// through Wm.logout(); everything else is the same on every setup.
Popout {
    id: root
    ipcNames: ["power"]

    property int selected: 0
    property int armed: -1

    readonly property var actions: [
        { key: "l", icon: "󰌾", label: "Lock",
          run: () => Quickshell.execDetached([Theme.configDir + "/scripts/lock"]) },
        { key: "o", icon: "󰌢", label: "Screen off",
          run: () => Quickshell.execDetached([Theme.configDir + "/scripts/screen-off"]) },
        { key: "e", icon: "󰍃", label: "Log out", confirm: "Log out?",
          run: () => Wm.logout() },
        { key: "r", icon: "󰜉", label: "Reboot", confirm: "Reboot?",
          run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
        { key: "s", icon: "󰐥", label: "Shut down", confirm: "Shut down?",
          run: () => Quickshell.execDetached(["systemctl", "poweroff"]) }
    ]

    centered: true
    cardWidth: 260
    cardHeight: rows.implicitHeight + 2 * cardPadding

    onVisibleChanged: {
        if (!visible)
            return
        selected = 0
        armed = -1
        // after Popout's own focus grab on open
        Qt.callLater(() => keys.forceActiveFocus())
    }

    function move(d) {
        armed = -1
        selected = (selected + d + actions.length) % actions.length
    }

    function activate(i) {
        const a = actions[i]
        selected = i
        if (a.confirm && armed !== i) {
            armed = i
            disarm.restart()
            return
        }
        armed = -1
        root.visible = false
        a.run()
    }

    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.armed = -1
    }

    Item {
        id: keys
        focus: true

        Keys.onPressed: event => {
            const k = event.key
            if (k === Qt.Key_Up || k === Qt.Key_K)
                root.move(-1)
            else if (k === Qt.Key_Down || k === Qt.Key_J)
                root.move(1)
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
                root.activate(root.selected)
            else if (k === Qt.Key_Escape && root.armed >= 0)
                root.armed = -1
            else {
                const i = root.actions.findIndex(a => a.key === event.text.toLowerCase())
                // unhandled (a plain Escape) goes on to Popout, which closes
                if (i < 0) {
                    event.accepted = false
                    return
                }
                root.activate(i)
            }
            event.accepted = true
        }
    }

    Column {
        id: rows
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 4

        Repeater {
            model: root.actions

            Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool armed: root.armed === index

                width: parent.width
                height: 40
                radius: 8
                color: armed ? Theme.red
                     : root.selected === index ? Qt.alpha(Theme.fg, 0.12) : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 12

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        // fixed column: the glyphs differ in width
                        width: 18
                        horizontalAlignment: Text.AlignHCenter
                        text: row.modelData.icon
                        color: row.armed ? Theme.bg
                             : row.modelData.confirm ? Theme.red : Theme.cyan
                        font.pixelSize: 16
                    }
                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.armed ? row.modelData.confirm : row.modelData.label
                        color: row.armed ? Theme.bg : Qt.alpha(Theme.fg, 0.9)
                        font.pixelSize: 13
                        font.bold: row.armed
                    }
                }

                // the row's letter, or what the second press needs once armed
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 20
                    width: hintText.implicitWidth + 12
                    radius: 4
                    color: row.armed ? "transparent" : Qt.alpha(Theme.fg, 0.08)
                    border.width: row.armed ? 0 : 1
                    border.color: Qt.alpha(Theme.fg, 0.16)

                    Txt {
                        id: hintText
                        anchors.centerIn: parent
                        text: row.armed ? "again to confirm" : row.modelData.key.toUpperCase()
                        color: row.armed ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: if (root.armed !== row.index) root.selected = row.index
                    onClicked: root.activate(row.index)
                }
            }
        }
    }
}
