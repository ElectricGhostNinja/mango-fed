import QtQuick
import Quickshell

// This output's focused window title, centered, quietly muted so it never
// fights the tags.
Txt {
    text: Wm.of(QsWindow.window?.screen?.name ?? "").title
    color: Qt.alpha(Theme.fg, 0.75)
    font.pixelSize: Theme.fontSize
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    Behavior on color { ColorAnimation { duration: 250 } }
}
