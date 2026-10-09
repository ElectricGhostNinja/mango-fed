import QtQuick

// On/off switch: a pill with a sliding knob. Dimmed while disabled.
Rectangle {
    property bool on: false
    property color onColor: Theme.accent
    signal toggled()

    width: 38
    height: 20
    radius: 10
    color: on ? onColor : Qt.alpha(Theme.fg, 0.15)
    opacity: enabled ? 1 : 0.4
    Behavior on color { ColorAnimation { duration: 150 } }

    Rectangle {
        x: parent.on ? parent.width - width - 3 : 3
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14; radius: 7
        color: parent.on ? Theme.bg : Qt.alpha(Theme.fg, 0.7)
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: parent.toggled()
    }
}
