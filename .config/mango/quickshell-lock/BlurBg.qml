import QtQuick
import QtQuick.Effects

// The wallpaper, blurred and dimmed (Qt's MultiEffect, from
// qml6-module-qtquick-effects). The effect's radius caps at 64 px,
// which is nothing on a 4K wallpaper, so it blurs a quarter-size copy
// and scales that up: a four-times-wider blur at a quarter the cost.
Item {
    Image {
        id: wall
        anchors.fill: parent
        source: root.wallpaper !== "" ? "file://" + root.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        visible: false
        layer.enabled: true
        layer.textureSize: Qt.size(Math.max(1, Math.round(width / 4)), Math.max(1, Math.round(height / 4)))
        layer.smooth: true
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        blurMultiplier: 0.5
        brightness: -0.08
        saturation: 0
    }
}
