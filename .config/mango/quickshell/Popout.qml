import QtQuick
import Quickshell
import Quickshell.Wayland

// Shared shell for every bar popup — Wayland edition. A full-screen
// transparent layer-shell overlay (the click catcher) with the styled
// card anchored under its bar item. Clicking anywhere outside the card
// closes it; Escape too. The window takes exclusive keyboard focus only
// while visible (an xdg-popup off a layer-shell panel never gets key
// events, which is why this is a layer surface and not PopupWindow).
// The same card chrome and behaviour as the X11 ports' Popout.
PanelWindow {
    id: root

    property Item anchorItem
    property real cardWidth: 300
    property real cardHeight: 300
    readonly property real cardPadding: 14
    // right-edge panel mode (control center) instead of centered-under-anchor
    property bool alignRight: false
    // floating in the middle of the output instead: for popups summoned
    // from the keyboard (keybinds, power) rather than from a bar module
    property bool centered: false

    default property alias content: inner.data

    // the whole card scales (Theme.popupScale), so popups lay themselves
    // out at 1080p sizes; these are the output's size in those units, for
    // popups that size themselves to the screen (keybinds, launcher)
    readonly property real s: Theme.popupScale
    readonly property real fitWidth: (screen ? screen.width : 1920) / s
    readonly property real fitHeight: (screen ? screen.height : 1080) / s

    visible: false
    color: "transparent"

    // the output whose bar owns the anchor item
    screen: (anchorItem && anchorItem.QsWindow.window) ? anchorItem.QsWindow.window.screen : null
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-popup"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // `qs ipc call <name> toggle`: BarIpc passes the call to every screen's
    // copy of this popup; the one on the focused output answers. Popups
    // with more verbs than toggle replace ipc().
    property var ipcNames: []
    readonly property bool onFocusedOutput: !screen || Wm.monitor === "" || screen.name === Wm.monitor
    function ipc(fn, arg) { if (fn === "toggle") visible = !visible }
    Connections {
        target: BarIpc
        enabled: root.ipcNames.length > 0
        function onCall(target, fn, arg) {
            if (root.ipcNames.indexOf(target) >= 0 && root.onFocusedOutput)
                root.ipc(fn, arg)
        }
    }

    // where the anchor sits on its own output. mapToGlobal answers in the
    // layout's coordinates, which include the output's position: with a
    // second monitor to the left, everything landed that monitor's width
    // too far right. This overlay covers one output, so take its origin off.
    property real ax: 0
    property real ay: 0

    onVisibleChanged: {
        if (visible && anchorItem) {
            const p = anchorItem.mapToGlobal(0, 0)
            ax = p.x - (screen ? screen.x : 0)
            ay = p.y - (screen ? screen.y : 0)
            inner.forceActiveFocus()
            enterAnim.restart()
        }
    }

    // catcher: any click outside the card closes
    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }

    Rectangle {
        id: card

        // placed by its on-screen (scaled) size
        readonly property real vw: width * root.s
        readonly property real vh: height * root.s
        scale: root.s
        transformOrigin: Item.TopLeft

        x: root.alignRight ? root.width - vw - 8
         : root.centered ? Math.round((root.width - vw) / 2)
         : Math.min(Math.max(root.ax + (root.anchorItem?.width ?? 0) / 2 - vw / 2, 8),
                    root.width - vw - 8)
        y: root.centered ? Math.round((root.height - vh) / 2)
         : root.ay + (root.anchorItem?.height ?? 0) + 12

        transform: Translate { id: slide; y: 0 }

        ParallelAnimation {
            id: enterAnim
            NumberAnimation { target: slide; property: "y"; from: -10; to: 0
                              duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1
                              duration: 160 }
        }
        width: root.cardWidth
        height: root.cardHeight
        // Centered popups (launcher, keybinds, power) look like mango's
        // floating windows, the network app among them: its focus border
        // (accent, the border-width slider's width) and corner radius, solid.
        // Drop-downs stay light: thin border, rounder, and a touch
        // translucent while mango blurs behind layers so the card frosts
        // over the desktop (solid again when blur is off).
        radius: root.centered ? Theme.barRadius : 12
        color: !root.centered && Wm.blur ? Qt.alpha(Theme.bg, 0.86) : Theme.bg
        border.width: root.centered ? Wm.borderpx : 1
        border.color: root.centered ? Theme.accent : Qt.alpha(Theme.accent, 0.4)

        Behavior on color { ColorAnimation { duration: 250 } }

        // swallow card clicks so they don't fall through to the catcher
        MouseArea { anchors.fill: parent }

        Item {
            id: inner
            anchors.fill: parent
            anchors.margins: root.cardPadding
            focus: true
            Keys.onEscapePressed: root.visible = false
        }
    }
}
