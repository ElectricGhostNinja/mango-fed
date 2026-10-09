import QtQuick
import Quickshell

// The bar window, effectiveBarHeight px tall. Under mango this is a
// wlr-layer-shell panel: the compositor reserves its exclusive zone and
// re-tiles live when the height changes — no struts, no placement fixups.
PanelWindow {
    id: root

    property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.effectiveBarHeight
    color: "transparent"
    // map once, at final size — see Theme.barStateReady
    visible: Theme.barStateReady

    Rectangle {
        id: panel
        anchors.fill: parent
        // inset from the screen edges; the gap below comes from mango's
        // outer gaps (same value), so the bar and windows share one margin
        anchors.topMargin: Theme.edgeInset
        anchors.leftMargin: Theme.edgeInset
        anchors.rightMargin: Theme.edgeInset
        anchors.bottomMargin: 0

        radius: Theme.barRadius
        color: Qt.alpha(Theme.bg, 0.94)
        border.width: 1
        border.color: Qt.alpha(Theme.accent, 0.35)

        Behavior on color { ColorAnimation { duration: 400 } }
        Behavior on border.color { ColorAnimation { duration: 400 } }

        // A portrait monitor or a small laptop panel cannot hold every
        // pill. When the two clusters would run into each other, the pills
        // that only repeat what another window shows step aside: media
        // first, then the CPU/RAM readout. Measured, not guessed: what the
        // rest needs is summed without those two, so hiding one cannot
        // change the answer and flip it back.
        readonly property real restWidth: {
            let w = leftCluster.width + 56
            const kids = rightCluster.children
            for (let i = 0; i < kids.length; i++) {
                const k = kids[i]
                if (k !== media && k !== metrics && k.visible)
                    w += k.width + rightCluster.spacing
            }
            return w
        }
        readonly property real metricsNeed: metrics.implicitWidth + rightCluster.spacing
        readonly property real mediaNeed: media.implicitWidth + rightCluster.spacing
        readonly property bool fitsMetrics: restWidth + metricsNeed <= width
        readonly property bool fitsMedia: restWidth + metricsNeed + mediaNeed <= width

        // right-click empty bar = the layout/tweaks picker (same popup
        // as clicking the layout button); declared before the clusters
        // so module mouse areas stack above it
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: layoutBtn.pickerVisible = !layoutBtn.pickerVisible
        }

        Row {
            id: leftCluster
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Launcher {}
            Tags {}
            LayoutButton { id: layoutBtn }
        }

        // Title lives in the gap between the clusters: screen-centered when
        // it fits, nudged inward when it doesn't, elided to the gap width.
        // (A symmetric clamp goes negative on narrow screens — the right
        // cluster is wide — and a negative-width Text ignores elide.)
        Title {
            anchors.verticalCenter: parent.verticalCenter
            readonly property real gapL: leftCluster.x + leftCluster.width + 24
            readonly property real gapR: rightCluster.x - 24
            width: Math.max(0, Math.min(implicitWidth, gapR - gapL))
            x: Math.max(gapL, Math.min((parent.width - width) / 2, gapR - width))
            visible: width > 40
        }

        Row {
            id: rightCluster
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Media { id: media; allowed: panel.fitsMedia }
            Weather {}
            Metrics { id: metrics; visible: panel.fitsMetrics }
            Volume {}
            Network {}
            Updates {}
            Tray {}
            Bell {}
            Clock {}
            MicMute {}
            CapsLock {}
            Screenshot {}
            Commands {}
        }
    }
}
