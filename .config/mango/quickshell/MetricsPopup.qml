import QtQuick
import Quickshell
import Quickshell.Io

// What's using the machine: CPU and RAM bars, then the busiest programs.
// Opens from the Metrics module. Per-program CPU comes from two
// scripts/procs snapshots a couple of seconds apart (ps would give the
// average since each process started), as a share of the whole machine,
// so the rows add up to the bar's CPU number. Processes group by program
// (helium ×12); click a column to sort. Sampling runs only while the card
// is open. btop, at the bottom, has the full picture.
//
// Ending a program: hover a row for ✕, click it (the row turns red and the
// list holds still), click the row again. That asks the listed processes
// to quit (SIGTERM, so apps can save); if any are still there 3 seconds
// later the row offers Force quit (SIGKILL). Only your own processes, and
// never the desktop's own: the shared list below plus Wm.sessionProcs.
Popout {
    id: root
    ipcNames: ["metrics"]

    property var groups: []        // every program: {name, count, cpu, rss, pids, killable}
    property string sortBy: "cpu"
    readonly property var rows: frozen ?? sorted(groups, sortBy).slice(0, maxRows)
    readonly property int maxRows: 6
    readonly property int rowHeight: 24

    property real memTotal: 0      // kB
    property real memAvail: 0
    property string load: ""
    property var prev: null        // last snapshot: {total, ticks: {pid: ticks}}

    // from scripts/sysinfo, same tick: local disks, disk activity, temps
    property var disks: []         // {mount, size, used (kB), fs, encrypted}
    property var ioPrev: null      // {r, w, t}: sector counters + time
    property real ioRead: -1       // bytes/s
    property real ioWrite: -1
    property var temps: ({})       // {cpu, gpu, drive} in °C, when present

    // network mounts (NAS), asked on their own with a time limit: an
    // unreachable server can hang anything that asks it for its size
    property var netMounts: []     // {mount, name, size, used, state: checking|ok|unreachable}

    // ending a program
    property string armed: ""      // name of the row waiting for its second click
    property var frozen: null      // the list as it was when armed, so rows don't move
    property var ending: ({})      // name → {pids, at, stuck}

    // processes every setup's session needs; Wm.sessionProcs adds the WM's own
    readonly property var sharedSessionProcs: /^(systemd|\(sd-pam\)|dbus-.*|pipewire.*|wireplumber|xdg-.*|gvfs.*|at-spi.*|dconf-service|gnome-keyring-daemon|ssh-agent|gpg-agent|lxpolkit|polkit-.*|dunst|qs|quickshell)$/

    cardWidth: 360
    cardHeight: col.implicitHeight + 2 * cardPadding

    onVisibleChanged: {
        disarm()
        if (visible) {
            prev = null
            groups = []
            ioPrev = null
            ioRead = ioWrite = -1
            sampler.running = true
            sysProc.running = true
            netMountsProc.running = true
            // a quick second snapshot so the list fills almost at once
            tick.interval = 700
            tick.restart()
        } else {
            tick.stop()
        }
    }

    Timer {
        id: tick
        repeat: true
        onTriggered: {
            interval = 2000
            sampler.running = true
            sysProc.running = true
        }
    }

    Process {
        id: sysProc
        command: [Theme.configDir + "/scripts/sysinfo"]
        stdout: StdioCollector {
            onStreamFinished: root.ingestSys(text)
        }
    }

    function ingestSys(t) {
        const disks = [], all = []
        let io = null
        for (const l of t.split("\n")) {
            const f = l.split("\t")
            if (f[0] === "disk" && f.length >= 4)
                disks.push({ mount: f[1], size: Number(f[2]), used: Number(f[3]),
                             fs: f[4] ?? "", encrypted: f[5] === "1" })
            else if (f[0] === "io")
                io = { r: Number(f[1]), w: Number(f[2]), t: Date.now() }
            else if (f[0] === "temp" && f.length === 4)
                all.push({ sensor: f[1], label: f[2], c: Number(f[3]) })
        }
        disks.sort((a, b) => (a.mount !== "/") - (b.mount !== "/") || a.mount.localeCompare(b.mount))
        root.disks = disks

        if (io && ioPrev && io.t > ioPrev.t) {
            const dt = (io.t - ioPrev.t) / 1000
            ioRead = Math.max(0, (io.r - ioPrev.r) * 512 / dt)
            ioWrite = Math.max(0, (io.w - ioPrev.w) * 512 / dt)
        }
        ioPrev = io

        // the one reading per part that means something: AMD k10temp Tctl,
        // Intel coretemp package, zenpower Tdie; amdgpu edge; the first
        // NVMe's composite (or a SATA drive via drivetemp)
        const pick = (sensor, labels) => all.find(x => x.sensor === sensor && (!labels || labels.includes(x.label)))
        const cpu = pick("k10temp", ["Tctl", "Tdie"]) ?? pick("coretemp", ["Package id 0"])
                  ?? pick("zenpower", ["Tdie", "Tctl"]) ?? pick("cpu_thermal")
        const gpu = pick("amdgpu", ["edge"]) ?? pick("nouveau")
        const drive = pick("nvme", ["Composite"]) ?? pick("drivetemp")
        const found = {}
        if (cpu) found.cpu = cpu.c
        if (gpu) found.gpu = gpu.c
        if (drive) found.drive = drive.c
        temps = found
    }

    // which network mounts exist: /proc/mounts, never touches the server
    Process {
        id: netMountsProc
        command: ["awk", "$3 ~ /^(cifs|smb3|nfs|nfs4|fuse\\.sshfs)$/ { print $2 }", "/proc/mounts"]
        stdout: StdioCollector {
            onStreamFinished: {
                // /proc/mounts writes spaces as \040
                const mounts = text.split("\n").filter(m => m !== "")
                    .map(m => m.replace(/\\040/g, " "))
                root.netMounts = mounts.map(m => ({ mount: m, name: m.split("/").pop() || m,
                                                   size: 0, used: 0, state: "checking" }))
                if (mounts.length) {
                    netDfProc.running = true
                    netTimeout.restart()
                }
            }
        }
    }

    // their sizes, within 3 seconds or not at all
    Process {
        id: netDfProc
        command: ["timeout", "-k", "1", "3", "df", "-P", "-t", "cifs", "-t", "smb3", "-t", "nfs",
                  "-t", "nfs4", "-t", "fuse.sshfs"]
        stdout: StdioCollector {
            onStreamFinished: {
                const sizes = {}
                for (const l of text.split("\n").slice(1)) {
                    const f = l.trim().split(/\s+/)
                    if (f.length >= 6)
                        sizes[f.slice(5).join(" ")] = { size: Number(f[1]), used: Number(f[2]) }
                }
                root.netMounts = root.netMounts.map(n => sizes[n.mount]
                    ? Object.assign({}, n, sizes[n.mount], { state: "ok" })
                    : Object.assign({}, n, { state: "unreachable" }))
                netTimeout.stop()
            }
        }
    }

    // a server that doesn't answer can leave df stuck past its own
    // timeout (uninterruptible I/O): say so instead of "checking" forever
    Timer {
        id: netTimeout
        interval: 5000
        onTriggered: root.netMounts = root.netMounts.map(n =>
            n.state === "checking" ? Object.assign({}, n, { state: "unreachable" }) : n)
    }

    Process {
        id: sampler
        command: [Theme.configDir + "/scripts/procs"]
        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
    }

    function isSession(name) {
        return sharedSessionProcs.test(name) || Wm.sessionProcs.test(name)
    }

    function ingest(t) {
        let total = 0, me = ""
        const ticks = {}, procs = []
        for (const l of t.split("\n")) {
            const f = l.split("\t")
            if (f[0] === "cpu")
                total = Number(f[1])
            else if (f[0] === "mem") {
                memTotal = Number(f[1])
                memAvail = Number(f[2])
            } else if (f[0] === "load")
                load = f[1]
            else if (f[0] === "me")
                me = f[1]
            else if (f.length === 5) {
                ticks[f[0]] = Number(f[1])
                procs.push({ pid: f[0], rss: Number(f[2]), uid: f[3], name: f[4] })
            }
        }
        if (prev && total > prev.total) {
            const dt = total - prev.total
            const byName = {}
            for (const p of procs) {
                let g = byName[p.name]
                if (!g)
                    g = byName[p.name] = { name: p.name, count: 0, cpu: 0, rss: 0, pids: [],
                                           killable: !isSession(p.name) }
                g.count++
                g.rss += p.rss
                g.pids.push(p.pid)
                // anyone else's process in the group (root, a service
                // user) and the group can't be ended from here
                if (p.uid !== me)
                    g.killable = false
                // new since the last snapshot: no baseline yet, counts 0
                if (p.pid in prev.ticks)
                    g.cpu += 100 * Math.max(0, ticks[p.pid] - prev.ticks[p.pid]) / dt
            }
            groups = Object.values(byName)
        }
        prev = { total: total, ticks: ticks }

        // programs being ended: drop the ones that are gone, and flag the
        // ones still running 3s after SIGTERM for a Force quit
        const next = {}
        for (const name in ending) {
            const e = ending[name]
            const alive = e.pids.filter(p => p in ticks)
            if (alive.length)
                next[name] = { pids: alive, at: e.at, stuck: Date.now() - e.at >= 3000 }
        }
        ending = next
    }

    function sorted(list, key) {
        return list.slice().sort((a, b) => b[key] - a[key] || b.rss - a.rss)
    }

    // one decimal only while it matters: 13.5G, but 937G (disk sizes
    // would otherwise crowd the meter's numbers)
    function mem(kb) {
        const unit = (v, u) => (v < 100 ? v.toFixed(1) : Math.round(v)) + u
        return kb >= 1073741824 ? unit(kb / 1073741824, "T")
             : kb >= 1048576 ? unit(kb / 1048576, "G") : Math.round(kb / 1024) + "M"
    }

    function rate(b) {
        return b < 1048576 ? (b / 1024).toFixed(b < 102400 ? 1 : 0) + " KB/s"
             : (b / 1048576).toFixed(1) + " MB/s"
    }

    function arm(g) {
        frozen = rows
        armed = g.name
        disarmTimer.restart()
    }

    function disarm() {
        armed = ""
        frozen = null
        disarmTimer.stop()
    }

    function end(g) {
        disarm()
        Quickshell.execDetached(["kill", "-s", "TERM"].concat(g.pids))
        const next = Object.assign({}, ending)
        next[g.name] = { pids: g.pids, at: Date.now(), stuck: false }
        ending = next
    }

    function forceQuit(name) {
        const e = ending[name]
        if (e)
            Quickshell.execDetached(["kill", "-s", "KILL"].concat(e.pids))
    }

    Timer {
        id: disarmTimer
        interval: 4000
        onTriggered: root.disarm()
    }

    function openBtop() {
        root.visible = false
        Quickshell.execDetached(["sh", "-c",
            "command -v btop >/dev/null && exec ghostty -e btop || " +
            "notify-send -a quickshell 'btop is not installed' 'sudo apt install btop'"])
    }

    // label · bar · value · detail
    component Meter: Item {
        property string tag
        property color tint
        property real value          // 0..100
        property string detail

        width: parent.width
        height: 20

        Txt {
            id: meterTag
            width: 40
            anchors.verticalCenter: parent.verticalCenter
            text: parent.tag
            color: parent.tint
            font.pixelSize: 12
            font.bold: true
        }
        Rectangle {
            id: track
            anchors.left: meterTag.right
            anchors.right: meterValue.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Qt.alpha(Theme.fg, 0.1)

            Rectangle {
                width: Math.min(Math.max(parent.parent.value, 0), 100) / 100 * parent.width
                height: parent.height
                radius: 3
                color: parent.parent.tint
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
        Txt {
            id: meterValue
            width: 36
            anchors.right: meterDetail.left
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: Math.round(parent.value) + "%"
            font.pixelSize: 12
        }
        Txt {
            id: meterDetail
            width: 92
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: parent.detail
            color: Qt.alpha(Theme.fg, 0.5)
        }
    }

    // column header that sorts on click
    component SortHeader: Txt {
        property string key
        text: key.toUpperCase() + (root.sortBy === key ? " ▾" : "")
        color: root.sortBy === key ? Theme.accent : Qt.alpha(Theme.fg, 0.45)
        horizontalAlignment: Text.AlignRight
        font.pixelSize: 10
        font.bold: true

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.disarm()
                root.sortBy = parent.key
            }
        }
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        Meter {
            tag: "CPU"
            tint: Theme.red
            // the bar's own number, so card and bar always agree
            value: Sys.cpu
            detail: root.load !== "" ? "load " + root.load : ""
        }
        Meter {
            tag: "RAM"
            tint: Theme.blue
            value: root.memTotal > 0 ? 100 * (1 - root.memAvail / root.memTotal) : Sys.mem
            detail: root.memTotal > 0
                ? root.mem(root.memTotal - root.memAvail) + " / " + root.mem(root.memTotal) : ""
        }

        // one reading per part, red when it's running hot
        Row {
            visible: root.temps.cpu !== undefined || root.temps.gpu !== undefined
                     || root.temps.drive !== undefined
            spacing: 14

            Repeater {
                model: [
                    { name: "CPU", c: root.temps.cpu, hot: 85 },
                    { name: "GPU", c: root.temps.gpu, hot: 85 },
                    { name: "NVMe", c: root.temps.drive, hot: 70 }
                ].filter(x => x.c !== undefined)

                Row {
                    id: tempItem
                    required property var modelData
                    spacing: 5
                    Txt {
                        text: tempItem.modelData.name
                        color: Qt.alpha(Theme.fg, 0.5)
                    }
                    Txt {
                        text: tempItem.modelData.c + "°"
                        color: tempItem.modelData.c >= tempItem.modelData.hot ? Theme.red : Theme.fg
                        font.bold: tempItem.modelData.c >= tempItem.modelData.hot
                    }
                }
            }
        }

        // local disks, the same meter as CPU and RAM
        Repeater {
            model: root.disks

            Meter {
                required property var modelData
                // a lock when the disk sits inside LUKS (Butterbian's
                // "Encrypt system"): encrypted at rest, at a glance
                tag: (modelData.mount === "/" ? "/" : modelData.mount.split("/").pop())
                     + (modelData.encrypted ? " 󰌾" : "")
                tint: Theme.yellow
                value: modelData.size > 0 ? 100 * modelData.used / modelData.size : 0
                detail: root.mem(modelData.used) + " / " + root.mem(modelData.size)
            }
        }

        // network mounts: size when the server answers, otherwise say so
        Repeater {
            model: root.netMounts

            Item {
                id: netRow
                required property var modelData
                width: parent.width
                height: 18

                Txt {
                    id: netGlyph
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰒍"
                    color: netRow.modelData.state === "unreachable" ? Qt.alpha(Theme.fg, 0.35) : Theme.cyan
                    font.pixelSize: 12
                }
                Txt {
                    anchors.left: netGlyph.right
                    anchors.leftMargin: 8
                    anchors.right: netVal.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: netRow.modelData.name
                    elide: Text.ElideRight
                    color: Qt.alpha(Theme.fg, 0.8)
                }
                Txt {
                    id: netVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: netRow.modelData.state === "ok"
                        ? root.mem(netRow.modelData.used) + " / " + root.mem(netRow.modelData.size)
                        : netRow.modelData.state === "checking" ? "checking…" : "not reachable"
                    color: netRow.modelData.state === "ok" ? Qt.alpha(Theme.fg, 0.6) : Qt.alpha(Theme.fg, 0.4)
                }
            }
        }

        // disk activity, like the network window's receiving / sending
        Txt {
            visible: root.ioRead >= 0
            text: "disk  read " + root.rate(root.ioRead) + "  ·  write " + root.rate(root.ioWrite)
            color: Qt.alpha(Theme.fg, 0.5)
        }

        Item {
            width: parent.width
            height: 18

            Txt {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "PROGRAM"
                color: Qt.alpha(Theme.fg, 0.45)
                font.pixelSize: 10
                font.bold: true
            }
            SortHeader {
                key: "cpu"
                width: 56
                anchors.right: memHeader.left
                anchors.verticalCenter: parent.verticalCenter
            }
            SortHeader {
                id: memHeader
                key: "rss"
                text: "MEM" + (root.sortBy === "rss" ? " ▾" : "")
                width: 64
                anchors.right: parent.right
                anchors.rightMargin: 30
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // fixed height: the card doesn't jump while the list fills or sorts
        Item {
            width: parent.width
            height: root.maxRows * root.rowHeight

            Txt {
                anchors.centerIn: parent
                visible: root.rows.length === 0
                text: "sampling…"
                color: Qt.alpha(Theme.fg, 0.4)
            }

            Column {
                width: parent.width

                Repeater {
                    model: root.rows

                    Item {
                        id: row
                        required property var modelData
                        readonly property bool armed: root.armed === modelData.name
                        readonly property var endingState: root.ending[modelData.name] ?? null
                        width: parent.width
                        height: root.rowHeight

                        // hover (and the second click once armed); declared
                        // first so the ✕ and Force quit buttons sit above it
                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: row.armed ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (row.armed) root.end(row.modelData)
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 2
                            anchors.bottomMargin: 2
                            radius: 5
                            visible: row.armed
                            color: Theme.red
                        }

                        // share of the top row's value in the sorted column
                        Rectangle {
                            readonly property real peak: root.rows[0]?.[root.sortBy] ?? 0
                            readonly property real v: row.modelData[root.sortBy]
                            visible: !row.armed
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            height: parent.height - 4
                            radius: 5
                            width: peak > 0 && v > 0 ? Math.max(2, v / peak * (parent.width - 30)) : 0
                            color: Qt.alpha(root.sortBy === "cpu" ? Theme.red : Theme.blue, 0.12)
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }

                        // name, then a dim ×N when the program runs as several processes
                        Txt {
                            id: nameText
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth,
                                            cpuText.x - x - 8 - (countText.visible ? countText.implicitWidth + 6 : 0))
                            elide: Text.ElideRight
                            text: row.armed ? "End " + row.modelData.name + "?" : row.modelData.name
                            color: row.armed ? Theme.bg
                                 : row.endingState ? Qt.alpha(Theme.fg, 0.45) : Theme.fg
                            font.pixelSize: 12
                            font.bold: row.armed
                        }
                        Txt {
                            id: countText
                            anchors.left: nameText.right
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.modelData.count > 1
                            text: "×" + row.modelData.count
                            color: row.armed ? Theme.bg : Qt.alpha(Theme.fg, 0.4)
                        }

                        // armed: what the second click does, over the number columns
                        Txt {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.armed
                            text: "click again to quit it"
                            color: Theme.bg
                        }

                        Txt {
                            id: cpuText
                            width: 56
                            anchors.right: memText.left
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            visible: !row.armed && !row.endingState
                            text: row.modelData.cpu.toFixed(1)
                            color: row.modelData.cpu >= 10 ? Theme.red : Qt.alpha(Theme.fg, 0.85)
                            font.pixelSize: 12
                        }
                        Txt {
                            id: memText
                            width: 64
                            anchors.right: parent.right
                            anchors.rightMargin: 30
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            visible: !row.armed && !row.endingState
                            text: root.mem(row.modelData.rss)
                            color: Qt.alpha(Theme.fg, 0.85)
                            font.pixelSize: 12
                        }

                        // SIGTERM sent: waiting, then Force quit if it's still around
                        Txt {
                            anchors.right: parent.right
                            anchors.rightMargin: 30
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!row.endingState && !row.endingState.stuck
                            text: "quitting…"
                            color: Qt.alpha(Theme.fg, 0.45)
                            font.italic: true
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!row.endingState && row.endingState.stuck
                            width: forceText.implicitWidth + 16
                            height: parent.height - 4
                            radius: 5
                            color: forceMa.containsMouse ? Theme.red : Qt.alpha(Theme.red, 0.2)

                            Txt {
                                id: forceText
                                anchors.centerIn: parent
                                text: "Force quit"
                                color: forceMa.containsMouse ? Theme.bg : Theme.red
                                font.bold: true
                            }

                            MouseArea {
                                id: forceMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.forceQuit(row.modelData.name)
                            }
                        }

                        // ✕ on hover, only for programs this card may end
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.modelData.killable && !row.armed && !row.endingState
                                     && (rowMa.containsMouse || xMa.containsMouse)
                            width: 20
                            height: 20
                            radius: 5
                            color: xMa.containsMouse ? Qt.alpha(Theme.red, 0.25) : "transparent"

                            Txt {
                                anchors.centerIn: parent
                                text: "✕"
                                color: xMa.containsMouse ? Theme.red : Qt.alpha(Theme.fg, 0.5)
                            }

                            MouseArea {
                                id: xMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.arm(row.modelData)
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.15)
        }

        Rectangle {
            width: parent.width
            height: 30
            radius: 8
            color: btopMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }

            Row {
                anchors.centerIn: parent
                spacing: 8

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍛"
                    color: Theme.cyan
                    font.pixelSize: 14
                }
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "open btop"
                    color: Qt.alpha(Theme.fg, 0.9)
                    font.pixelSize: 12
                }
            }

            MouseArea {
                id: btopMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openBtop()
            }
        }
    }
}
