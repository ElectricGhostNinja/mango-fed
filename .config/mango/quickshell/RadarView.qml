import QtQuick
import Quickshell
import Quickshell.Io

// Weather radar: the last hour of RainViewer's mosaic looping over Esri's
// dark basemap, centred on the forecast's spot. scripts/radar fetches the
// 3x3 tile block into ~/.cache/mango/radar and prints where; this draws
// it — land, rain, then place names on top so they stay readable.
// The corner buttons and the wheel zoom (capped where the mosaic runs
// out of detail), the time chip pauses the loop, and a click on the map
// opens the same spot on Windy's radar in the browser for a proper look.
// While the card is open the frames refresh every five minutes.
Item {
    id: view

    property real lat: 0
    property real lon: 0
    property int zoom: 7          // wanted; 5 = a few states, 8 = the city
    property bool active: false   // fetch + animate only while shown

    // what's on screen (from the last successful fetch)
    property int tz: 7
    property real cx: 0
    property real cy: 0
    property string baseDir: ""
    property var frames: []       // {t, dir}, oldest first
    property int frame: 0
    property bool paused: false
    property bool loading: false
    property string error: ""

    readonly property int ix: Math.floor(cx)
    readonly property int iy: Math.floor(cy)
    readonly property int n: 1 << tz

    clip: true

    function refetch() {
        fetch.running = false
        fetch.running = true
    }
    onActiveChanged: active ? refetch() : fetch.running = false
    onZoomChanged: if (active) refetch()

    property string _err: ""
    Process {
        id: fetch
        command: [Theme.configDir + "/scripts/radar", String(view.lat), String(view.lon), String(view.zoom)]
        onRunningChanged: if (running) { view.loading = true; view._err = "" }
        stdout: StdioCollector { onStreamFinished: view.parse(text) }
        stderr: StdioCollector { onStreamFinished: view._err = text.trim() }
        onExited: (code, st) => {
            if (st !== 0)
                return
            view.loading = false
            if (code !== 0 && view.frames.length === 0)
                view.error = view._err !== "" ? view._err.replace(/^radar: /, "") : "couldn't load the radar"
        }
    }

    function parse(text) {
        const fr = []
        let z = zoom, x = cx, y = cy, dir = baseDir
        for (const line of text.split("\n")) {
            const p = line.split(" ")
            if (p[0] === "zoom")
                z = parseInt(p[1])
            else if (p[0] === "center") {
                x = parseFloat(p[1])
                y = parseFloat(p[2])
            } else if (p[0] === "base")
                dir = p.slice(1).join(" ")
            else if (p[0] === "frame")
                fr.push({ t: parseInt(p[1]), dir: p.slice(2).join(" ") })
        }
        if (fr.length === 0)
            return
        // one assignment each, tiles keyed by z so nothing shows half-moved
        view.tz = z
        cx = x
        cy = y
        baseDir = dir
        frames = fr
        frame = fr.length - 1
        error = ""
    }

    // loop: 10-minute frames at ~2/s, a longer hold on the newest
    Timer {
        interval: view.frame === view.frames.length - 1 ? 1800 : 450
        repeat: true
        running: view.active && view.frames.length > 1 && !view.paused
        onTriggered: view.frame = (view.frame + 1) % view.frames.length
    }
    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: view.active
        onTriggered: view.refetch()
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.fg, 0.05)
    }

    // the 3x3 block around the centre tile, each layer a cached file
    Repeater {
        model: view.baseDir !== "" ? 9 : 0

        Item {
            id: tile
            required property int index
            readonly property int dx: index % 3 - 1
            readonly property int dy: Math.floor(index / 3) - 1
            readonly property string name: view.tz + "_" + ((view.ix + dx + view.n) % view.n) + "_" + (view.iy + dy)
            x: Math.round((view.ix + dx - view.cx) * 256 + view.width / 2)
            y: Math.round((view.iy + dy - view.cy) * 256 + view.height / 2)
            width: 256
            height: 256

            Image {
                anchors.fill: parent
                source: "file://" + view.baseDir + "/" + tile.name + ".jpg"
                asynchronous: true
            }
            // every frame loaded, only one shown: no reload flicker
            Repeater {
                model: view.frames
                Image {
                    required property var modelData
                    required property int index
                    anchors.fill: parent
                    visible: index === view.frame
                    opacity: 0.85
                    source: "file://" + modelData.dir + "/" + tile.name + ".png"
                    asynchronous: true
                }
            }
            Image {
                anchors.fill: parent
                source: "file://" + view.baseDir + "/" + tile.name + "_ref.png"
                asynchronous: true
            }
        }
    }

    // you are here
    Rectangle {
        visible: view.frames.length > 0
        anchors.centerIn: parent
        width: 10; height: 10; radius: 5
        color: Theme.accent
        border.width: 2
        border.color: Theme.bg
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["xdg-open",
            "https://www.windy.com/-Weather-radar-radar?radar," + view.lat.toFixed(3)
            + "," + view.lon.toFixed(3) + "," + view.tz])
        onWheel: wheel => view.zoom = Math.max(5, Math.min(8, view.zoom + (wheel.angleDelta.y > 0 ? 1 : -1)))
    }

    Txt {
        visible: view.frames.length === 0
        anchors.centerIn: parent
        text: view.error !== "" ? "󰅙 " + view.error : "loading radar…"
        color: view.error !== "" ? Theme.red : Qt.alpha(Theme.fg, 0.5)
    }

    // frame time, bottom left
    Rectangle {
        visible: view.frames.length > 0
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 6
        width: timeText.implicitWidth + 14
        height: 20
        radius: 6
        color: Qt.alpha(Theme.bg, timeMa.containsMouse ? 0.95 : 0.8)

        MouseArea {
            id: timeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.paused = !view.paused
        }

        Txt {
            id: timeText
            anchors.centerIn: parent
            text: (view.paused ? "󰏤 " : "") + (view.frames[view.frame]
                  ? Qt.formatTime(new Date(view.frames[view.frame].t * 1000), "h:mm AP") : "")
                  + (view.loading ? " · updating" : "")
            color: view.frame === view.frames.length - 1 ? Theme.fg : Qt.alpha(Theme.fg, 0.6)
            font.pixelSize: 10
        }
    }

    // zoom, bottom right
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        spacing: 4

        Repeater {
            model: [{ glyph: "󰍴", d: -1 }, { glyph: "󰐕", d: 1 }]

            Rectangle {
                id: zb
                required property var modelData
                readonly property bool can: view.zoom + modelData.d >= 5 && view.zoom + modelData.d <= 8
                width: 22; height: 20; radius: 6
                color: Qt.alpha(Theme.bg, zbMa.containsMouse ? 0.95 : 0.8)

                Txt {
                    anchors.centerIn: parent
                    text: zb.modelData.glyph
                    color: zb.can ? Theme.fg : Theme.disabled
                }
                MouseArea {
                    id: zbMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: zb.can
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.zoom += zb.modelData.d
                }
            }
        }
    }

    // the map makers' due
    Txt {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 4
        text: "Esri · RainViewer"
        color: Qt.alpha(Theme.fg, 0.4)
        font.pixelSize: 8
    }
}
