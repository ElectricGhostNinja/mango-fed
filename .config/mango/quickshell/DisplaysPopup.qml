import QtQuick
import Quickshell
import Quickshell.Io

// Displays (launcher, command menu): arrange, size, rotate and switch
// outputs without leaving the desktop. wlr-randr does the work and the
// compositor answers live, so every change is a trial: 15 seconds to
// keep it or it comes back — a mode the monitor can't show never leaves
// you blind. Kept layouts go to displays.conf, which scripts/displays
// puts back on every bar start (mango's monitorrule stays the fallback).
// Drag the diagram to arrange; edges snap to their neighbours.
Popout {
    id: root
    ipcNames: ["displays"]

    property var outs: []      // editable {name, desc, on, w, h, r, x, y, scale, transform, vrr, modes}
    property var orig: []      // as the compositor has it now
    property var before: []    // the layout a trial replaced, for revert
    property int sel: 0
    property bool _picked: false   // the user chose a tile; keep it across reloads
    property string pick: ""   // the expanded picker: "res" | "rate" | ""
    property bool busy: false
    property int keepLeft: 0   // trial countdown, 0 = none running
    property string status: ""

    readonly property var cur: outs[sel] ?? null
    readonly property var live: outs.filter(o => o.on)
    readonly property bool dirty: JSON.stringify(outs.map(strip)) !== JSON.stringify(orig.map(strip))
    readonly property var scales: {
        const s = [1, 1.25, 1.5, 1.75, 2]
        if (cur && !s.includes(cur.scale)) s.push(cur.scale)
        return s.sort((a, b) => a - b)
    }
    readonly property var rotations: [
        { t: "normal", l: "0°" }, { t: "90", l: "90°" }, { t: "180", l: "180°" }, { t: "270", l: "270°" }]
    // the selected output's resolutions (largest first) and the rates of
    // the one it's on (fastest first)
    readonly property var resolutions: {
        if (!cur) return []
        const seen = {}, out = []
        for (const m of cur.modes) {
            const k = m.w + "x" + m.h
            if (seen[k]) { if (m.preferred) seen[k].preferred = true; continue }
            seen[k] = { w: m.w, h: m.h, preferred: m.preferred }
            out.push(seen[k])
        }
        return out.sort((a, b) => b.w * b.h - a.w * a.h || b.w - a.w)
    }
    readonly property var rates: cur
        ? [...new Set(cur.modes.filter(m => m.w === cur.w && m.h === cur.h).map(m => m.r))].sort((a, b) => b - a)
        : []

    centered: true
    cardWidth: 840
    cardHeight: 500

    onVisibleChanged: {
        if (visible) {
            pick = ""
            status = ""
            _picked = false
            loader.running = true
        } else {
            Wm.identifyOutputs = false
            if (keepLeft > 0)
                revert()
        }
    }

    function strip(o) { return [o.name, o.on, o.w, o.h, o.r, o.x, o.y, o.scale, o.transform, o.vrr] }
    function clone(a) { return JSON.parse(JSON.stringify(a)) }
    function same(a, b) { return JSON.stringify(strip(a)) === JSON.stringify(strip(b)) }
    // logical size: what the desktop sees after scale and rotation
    function lw(o) { return Math.round((o.transform === "90" || o.transform === "270" ? o.h : o.w) / o.scale) }
    function lh(o) { return Math.round((o.transform === "90" || o.transform === "270" ? o.w : o.h) / o.scale) }
    function modeStr(o) { return o.w + "x" + o.h + "@" + o.r }

    Process {
        id: loader
        command: [Theme.configDir + "/scripts/displays", "list"]
        stdout: StdioCollector { onStreamFinished: root.load(text) }
    }

    function load(text) {
        let j
        try { j = JSON.parse(text) } catch (e) { status = "wlr-randr isn't installed"; return }
        const list = []
        for (const o of j) {
            const m = o.modes.find(m => m.current) ?? o.modes.find(m => m.preferred) ?? o.modes[0]
                      ?? { width: 0, height: 0, refresh: 0 }
            const desc = [o.make, o.model].filter(x => x && x !== "Unknown").join(" ")
            list.push({
                name: o.name, desc: desc !== "" ? desc : (o.description ?? o.name),
                on: !!o.enabled, w: m.width, h: m.height, r: Math.round(m.refresh * 1000) / 1000,
                x: o.position?.x ?? 0, y: o.position?.y ?? 0, scale: o.scale ?? 1,
                transform: o.transform ?? "normal", vrr: o.adaptive_sync === true,
                serial: o.serial && o.serial !== "Unknown" ? o.serial : "",
                ident: [o.make, o.model, o.serial].map(x => x ?? "").join("|"),
                inches: o.physical_size && o.physical_size.width > 0
                    ? Math.round(Math.hypot(o.physical_size.width, o.physical_size.height) / 25.4) : 0,
                maxRes: o.modes.reduce((b, m) => m.width * m.height > b.w * b.h ? { w: m.width, h: m.height } : b,
                                       { w: 0, h: 0 }),
                modes: o.modes.map(m => ({ w: m.width, h: m.height,
                                          r: Math.round(m.refresh * 1000) / 1000, preferred: !!m.preferred }))
            })
        }
        orig = clone(list)
        outs = list
        if (!_picked || sel >= outs.length) {
            const here = outs.findIndex(o => root.screen && o.name === root.screen.name)
            sel = here >= 0 ? here : 0
        }
    }

    // change one field of the selected output — a new array, so the
    // diagram and the pickers rebind
    function set(field, value) {
        const a = clone(outs)
        const o = a[sel]
        o[field] = value
        if (field === "w" || field === "h") {
            const rs = o.modes.filter(m => m.w === o.w && m.h === o.h).map(m => m.r)
            if (!rs.includes(o.r))
                o.r = Math.max(...rs)
        }
        outs = normalise(a)
    }
    function setRes(w, h) {
        const a = clone(outs)
        const o = a[sel]
        o.w = w
        o.h = h
        const rs = o.modes.filter(m => m.w === w && m.h === h).map(m => m.r)
        if (!rs.includes(o.r))
            o.r = Math.max(...rs)
        outs = normalise(a)
    }
    // the layout's top-left corner is the origin
    function normalise(a) {
        const on = a.filter(o => o.on)
        if (on.length === 0)
            return a
        const mx = Math.min(...on.map(o => o.x)), my = Math.min(...on.map(o => o.y))
        for (const o of a) {
            o.x -= mx
            o.y -= my
        }
        return a
    }
    // drag end: snap the moved output's edges to its neighbours' (thr is
    // in logical pixels — the stage passes a hand's width of its own),
    // then make sure it overlaps nothing by nudging it off the nearest side
    function place(i, x, y, thr) {
        const a = clone(outs)
        const o = a[i]
        let bx = x, by = y, dx = thr, dy = thr
        for (let k = 0; k < a.length; k++) {
            if (k === i || !a[k].on)
                continue
            const b = a[k]
            for (const cx of [b.x + lw(b), b.x - lw(o), b.x, b.x + lw(b) - lw(o)])
                if (Math.abs(cx - x) < dx) { dx = Math.abs(cx - x); bx = cx }
            for (const cy of [b.y + lh(b), b.y - lh(o), b.y, b.y + lh(b) - lh(o)])
                if (Math.abs(cy - y) < dy) { dy = Math.abs(cy - y); by = cy }
        }
        o.x = Math.round(bx)
        o.y = Math.round(by)
        for (let k = 0; k < a.length; k++) {
            if (k === i || !a[k].on)
                continue
            const b = a[k]
            const ox = Math.min(o.x + lw(o), b.x + lw(b)) - Math.max(o.x, b.x)
            const oy = Math.min(o.y + lh(o), b.y + lh(b)) - Math.max(o.y, b.y)
            if (ox <= 0 || oy <= 0)
                continue
            // the shorter way out wins; sideways over up/down on a tie
            if (ox <= oy)
                o.x = o.x + lw(o) / 2 < b.x + lw(b) / 2 ? b.x - lw(o) : b.x + lw(b)
            else
                o.y = o.y + lh(o) / 2 < b.y + lh(b) / 2 ? b.y - lh(o) : b.y + lh(b)
        }
        outs = normalise(a)
    }

    // wlr-randr arguments for every output that differs between the two
    function argsFor(to, from) {
        const args = []
        for (const o of to) {
            const p = from.find(q => q.name === o.name)
            if (p && same(p, o))
                continue
            args.push("--output", o.name)
            if (!o.on) {
                args.push("--off")
                continue
            }
            args.push("--on", "--mode", modeStr(o), "--pos", o.x + "," + o.y,
                      "--scale", String(o.scale), "--transform", o.transform,
                      "--adaptive-sync", o.vrr ? "enabled" : "disabled")
        }
        return args
    }

    property var _err: []
    property string _after: ""
    Process {
        id: randr
        stderr: SplitParser { onRead: l => { if (l.trim() !== "") root._err.push(l.trim()) } }
        onExited: (code, st) => {
            root.busy = false
            if (code !== 0) {
                root.status = root._err.length ? root._err[root._err.length - 1] : "wlr-randr failed"
                root.keepLeft = 0
            } else if (root._after === "trial") {
                root.keepLeft = 15
                root.status = ""
            } else {
                root.status = "reverted"
            }
            loader.running = true
        }
    }
    function runRandr(args, after) {
        if (busy || args.length === 0)
            return
        busy = true
        _err = []
        _after = after
        randr.command = ["wlr-randr"].concat(args)
        randr.running = true
    }
    function apply() {
        before = clone(orig)
        runRandr(argsFor(outs, orig), "trial")
    }
    function revert() {
        keepLeft = 0
        runRandr(argsFor(before, outs), "revert")
    }
    function keep() {
        keepLeft = 0
        const text = outs.map(o => [o.name, o.on ? "on" : "off", modeStr(o), o.x + "," + o.y,
                                    o.scale, o.transform, o.vrr ? 1 : 0, o.ident].join("\t")).join("\n")
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" | "$0" save',
                                 Theme.configDir + "/scripts/displays", text])
        status = "kept · restored on every start"
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.keepLeft > 0
        onTriggered: {
            root.keepLeft--
            if (root.keepLeft === 0)
                root.revert()
        }
    }
    Timer {
        id: identTimer
        interval: 2500
        onTriggered: Wm.identifyOutputs = false
    }

    // --- pieces ---
    component Pill: Rectangle {
        property string label
        property bool active: false
        property bool star: false
        signal clicked()
        width: pillText.implicitWidth + 18
        height: 24
        radius: 8
        color: active ? Theme.accent
             : pillMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)
        Behavior on color { ColorAnimation { duration: 120 } }
        Txt {
            id: pillText
            anchors.centerIn: parent
            text: label + (star ? " ★" : "")
            color: active ? Theme.bg : Qt.alpha(Theme.fg, 0.85)
            font.bold: active
        }
        MouseArea {
            id: pillMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
    component Label: Txt {
        color: Qt.alpha(Theme.fg, 0.6)
    }
    // "Resolution      3440 × 1440 ▾" — click to expand its pills below
    component PickRow: Item {
        property string label
        property string value
        property string key
        width: parent.width
        height: 28
        Label { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: label }
        Pill {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: value + (root.pick === key ? "  󰅃" : "  󰅀")
            active: false
            onClicked: root.pick = root.pick === key ? "" : key
        }
    }

    // --- left: the diagram ---
    Item {
        id: canvas
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 76
        width: 480

        readonly property real bw: Math.max(1, ...root.live.map(o => o.x + root.lw(o)))
        readonly property real bh: Math.max(1, ...root.live.map(o => o.y + root.lh(o)))
        readonly property real k: Math.min((width - 40) / bw, (height - 60) / bh, 0.18)
        readonly property real ox: (width - bw * k) / 2
        readonly property real oy: 8 + (height - 44 - bh * k) / 2
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.alpha(Theme.fg, 0.04)
        }

        Repeater {
            model: root.outs

            Rectangle {
                id: mon
                required property var modelData
                required property int index
                readonly property bool selected: index === root.sel
                visible: modelData.on
                x: canvas.ox + modelData.x * canvas.k
                y: canvas.oy + modelData.y * canvas.k
                width: root.lw(modelData) * canvas.k
                height: root.lh(modelData) * canvas.k
                radius: 6
                color: selected ? Qt.alpha(Theme.accent, 0.22) : Qt.alpha(Theme.fg, 0.08)
                border.width: selected ? 2 : 1
                border.color: selected ? Theme.accent : Qt.alpha(Theme.fg, 0.25)
                z: monMa.drag.active ? 2 : selected ? 1 : 0

                // name and model up top, mode and placement along the
                // bottom; a small tile keeps just the name
                readonly property bool roomy: width >= 140 && height >= 76
                clip: true

                Column {
                    anchors.left: mon.roomy ? parent.left : undefined
                    anchors.top: mon.roomy ? parent.top : undefined
                    anchors.margins: 10
                    anchors.centerIn: mon.roomy ? undefined : parent
                    spacing: 2
                    Txt {
                        text: mon.modelData.name
                        color: mon.selected ? Theme.accent : Theme.fg
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Txt {
                        visible: mon.roomy
                        width: mon.width - 20
                        text: mon.modelData.desc + (mon.modelData.inches ? " " + mon.modelData.inches + "\"" : "")
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
                Column {
                    visible: mon.roomy
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    spacing: 1
                    Txt {
                        text: mon.modelData.w + "×" + mon.modelData.h + " @ " + mon.modelData.r + " Hz"
                        color: Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: 10
                    }
                    Txt {
                        text: "scale " + mon.modelData.scale + "  ·  at " + mon.modelData.x + "," + mon.modelData.y
                              + (mon.modelData.transform !== "normal" ? "  ·  " + mon.modelData.transform + "°" : "")
                        color: Qt.alpha(Theme.fg, 0.5)
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    id: monMa
                    anchors.fill: parent
                    cursorShape: root.live.length > 1 ? Qt.OpenHandCursor : Qt.PointingHandCursor
                    // past the stage's edges too: the layout fills the
                    // stage, so "left of the first screen" starts outside it
                    drag.target: root.live.length > 1 && root.keepLeft === 0 ? mon : undefined
                    drag.minimumX: -mon.width + 20
                    drag.minimumY: -mon.height + 20
                    drag.maximumX: canvas.width - 20
                    drag.maximumY: canvas.height - 20
                    onPressed: { root.sel = mon.index; root._picked = true }
                    onReleased: {
                        if (drag.active)
                            root.place(mon.index, (mon.x - canvas.ox) / canvas.k, (mon.y - canvas.oy) / canvas.k,
                                       40 / canvas.k)
                    }
                }
            }
        }

        // switched-off outputs wait along the bottom
        Row {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 10
            spacing: 6
            Repeater {
                model: root.outs.map((o, i) => ({ o: o, i: i })).filter(e => !e.o.on)
                Pill {
                    required property var modelData
                    label: "󰶐  " + modelData.o.name + " · off"
                    active: modelData.i === root.sel
                    onClicked: { root.sel = modelData.i; root._picked = true }
                }
            }
        }
    }

    // the selected output's hardware, under the stage
    Grid {
        id: hardware
        anchors.left: parent.left
        anchors.top: canvas.bottom
        anchors.topMargin: 8
        width: canvas.width
        columns: 2
        columnSpacing: 20
        rowSpacing: 2
        visible: root.cur !== null

        Repeater {
            model: root.cur ? [
                ["connector", root.cur.name],
                ["model", root.cur.desc],
                ["max resolution", root.cur.maxRes.w + " × " + root.cur.maxRes.h],
                ["panel", root.cur.inches ? root.cur.inches + "\"" : "—"],
                ["serial", root.cur.serial !== "" ? root.cur.serial : "—"],
                ["", root.live.length > 1 ? "drag a display to arrange" : ""]
            ] : []
            Row {
                required property var modelData
                width: (hardware.width - hardware.columnSpacing) / 2
                spacing: 8
                Txt {
                    width: 88
                    text: parent.modelData[0]
                    color: Qt.alpha(Theme.fg, 0.45)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                Txt {
                    width: parent.width - 96
                    text: parent.modelData[1]
                    color: Qt.alpha(Theme.fg, 0.8)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }
    }

    // --- right: the selected output ---
    Column {
        id: panel
        anchors.left: canvas.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: buttons.top
        anchors.bottomMargin: 8
        spacing: 6
        visible: root.cur !== null
        clip: true

        Txt {
            width: parent.width
            text: root.cur ? root.cur.desc : ""
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
        }
        Txt {
            width: parent.width
            text: root.cur ? root.cur.name + "  ·  " + root.cur.w + " × " + root.cur.h + " @ " + root.cur.r + " Hz" : ""
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: 10
            elide: Text.ElideRight
        }
        Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.fg, 0.1) }

        Item {
            width: parent.width
            height: 28
            Label { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Enabled" }
            Toggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                on: root.cur ? root.cur.on : false
                // the last screen on can't be switched off from here
                enabled: root.cur && (!root.cur.on || root.live.length > 1)
                onToggled: root.set("on", !root.cur.on)
            }
        }

        PickRow {
            label: "Resolution"
            key: "res"
            value: root.cur ? root.cur.w + " × " + root.cur.h : ""
        }
        Flow {
            visible: root.pick === "res"
            width: parent.width
            spacing: 4
            Repeater {
                model: root.resolutions
                Pill {
                    required property var modelData
                    label: modelData.w + "×" + modelData.h
                    star: modelData.preferred
                    active: root.cur && modelData.w === root.cur.w && modelData.h === root.cur.h
                    onClicked: { root.setRes(modelData.w, modelData.h); root.pick = "" }
                }
            }
        }

        PickRow {
            label: "Refresh rate"
            key: "rate"
            value: root.cur ? root.cur.r + " Hz" : ""
        }
        Flow {
            visible: root.pick === "rate"
            width: parent.width
            spacing: 4
            Repeater {
                model: root.rates
                Pill {
                    required property var modelData
                    label: modelData + " Hz"
                    active: root.cur && modelData === root.cur.r
                    onClicked: { root.set("r", modelData); root.pick = "" }
                }
            }
        }

        Label { text: "Scale" }
        Row {
            spacing: 4
            Repeater {
                model: root.scales
                Pill {
                    required property var modelData
                    label: Math.round(modelData * 100) + "%"
                    active: root.cur && modelData === root.cur.scale
                    onClicked: root.set("scale", modelData)
                }
            }
        }

        Label { text: "Rotation" }
        Row {
            spacing: 4
            Repeater {
                model: root.rotations
                Pill {
                    required property var modelData
                    label: modelData.l
                    active: root.cur && modelData.t === root.cur.transform
                    onClicked: root.set("transform", modelData.t)
                }
            }
        }

        Item {
            width: parent.width
            height: 28
            Label { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Variable refresh rate" }
            Toggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                on: root.cur ? root.cur.vrr : false
                onToggled: root.set("vrr", !root.cur.vrr)
            }
        }
    }

    // --- apply / trial ---
    Item {
        id: buttons
        anchors.left: canvas.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 48

        Txt {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            text: root.keepLeft > 0 ? "keep these settings?  reverting in " + root.keepLeft + " s"
                : root.busy ? "applying…" : root.status
            color: root.keepLeft > 0 ? Theme.fg
                 : root.status !== "" && root.status !== "reverted" && !root.status.startsWith("kept") ? Theme.red
                 : Qt.alpha(Theme.fg, 0.5)
            elide: Text.ElideRight
        }

        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 6

            Pill {
                label: "identify"
                active: Wm.identifyOutputs
                onClicked: { Wm.identifyOutputs = true; identTimer.restart() }
            }
            Pill {
                visible: root.keepLeft === 0
                label: "apply"
                active: root.dirty && !root.busy
                opacity: root.dirty ? 1 : 0.5
                onClicked: if (root.dirty && !root.busy) root.apply()
            }
            Pill {
                visible: root.keepLeft > 0
                label: "revert"
                onClicked: root.revert()
            }
            Pill {
                visible: root.keepLeft > 0
                label: "keep"
                active: true
                onClicked: root.keep()
            }
        }
    }
}
