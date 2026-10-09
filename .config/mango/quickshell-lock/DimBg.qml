import QtQuick

// The wallpaper, dimmed — the fallback when the blur module isn't there
Item {
    Image {
        anchors.fill: parent
        source: root.wallpaper !== "" ? "file://" + root.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.bg, 0.6)
    }
}
