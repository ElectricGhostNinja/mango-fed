import QtQuick
import Quickshell
import Quickshell.Widgets

// 12 bspwm desktops: focused = wide accent pill, occupied = numbered cell,
// empty = small dot. Widths and colors animate on every report line.
// With the "Tag icons" toggle on, an occupied cell also carries the icons
// of the apps on it (one per app, at most three), so the strip answers
// "where did I leave Firefox" by itself.
Item {
    id: strip
    // this bar's output: its tags, not the focused monitor's
    readonly property string mon: QsWindow.window?.screen?.name ?? ""
    readonly property var st: Wm.of(mon)
    readonly property var monApps: Wm.tagApps[mon] ?? ({})

    implicitWidth: tagRow.implicitWidth
    implicitHeight: Math.round(22 * Theme.barScale)

    WheelHandler {
        onWheel: ev => Wm.cycleTag(ev.angleDelta.y > 0 ? -1 : 1, strip.mon)
    }

    Row {
        id: tagRow
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: strip.st.tagCount

            Rectangle {
                id: tag
                required property int index
                readonly property bool selected: (strip.st.seltags & (1 << index)) !== 0
                readonly property bool occupied: (strip.st.occtags & (1 << index)) !== 0
                readonly property bool urgent: (strip.st.urgtags & (1 << index)) !== 0
                readonly property var apps: Theme.tagIcons ? (strip.monApps[index] ?? []).slice(0, 3) : []
                readonly property int iconPx: Math.round(14 * Theme.barScale)

                width: Math.round((selected ? 30 : occupied ? 22 : 12) * Theme.barScale)
                       + apps.length * (iconPx + Math.round(3 * Theme.barScale))
                height: Math.round(22 * Theme.barScale)
                radius: Math.round(7 * Theme.barScale)
                anchors.verticalCenter: parent.verticalCenter
                color: urgent ? Theme.red
                     : selected ? Theme.selbg
                     : occupied ? Qt.alpha(Theme.fg, 0.08)
                     : "transparent"

                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 180 } }

                SequentialAnimation on opacity {
                    running: tag.urgent
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.5; duration: 500; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Math.round(3 * Theme.barScale)
                    visible: tag.occupied || tag.selected

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tag.index + 1
                        color: tag.urgent ? Theme.bg
                             : tag.selected ? Theme.selfg
                             : Qt.alpha(Theme.fg, 0.85)
                        font.pixelSize: Math.round(12 * Theme.barScale)
                        font.bold: tag.selected
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    Repeater {
                        model: tag.apps
                        IconImage {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: tag.iconPx
                            source: modelData.icon
                            opacity: tag.selected || tag.urgent ? 1 : 0.85
                        }
                    }
                }

                Rectangle {
                    visible: !tag.occupied && !tag.selected
                    anchors.centerIn: parent
                    width: Math.round(5 * Theme.barScale)
                    height: width
                    radius: width / 2
                    color: Qt.alpha(Theme.fg, 0.25)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: m => {
                        if (m.button === Qt.MiddleButton)
                            Wm.sendToTag(tag.index, strip.mon)
                        else
                            Wm.viewTag(tag.index, strip.mon)
                    }
                }
            }
        }
    }
}
