pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Lightweight system state for the bar, built to cost nothing while idle:
//   cpu / memory / battery   files read in-process on a 3 s tick (no shell)
//   caps lock                the keyboard LED files, read in-process each second
//   mic mute                 Pipewire tells us; nothing is polled
//   disk, do-not-disturb     one small process a minute (and right after a toggle)
//   network                  follows `nmcli monitor` — connect, drop, VPN,
//                            connectivity show at once; on Wi-Fi only, the
//                            signal strength is asked for every 30 s
Singleton {
    id: root

    property real cpu: 0
    property real mem: 0
    property real disk: 0
    property real battery: 0
    property bool batteryCharging: false
    property string netName: ""
    property string netType: ""
    property bool vpnOn: false
    property string vpnName: ""
    property int wifiSignal: -1        // 0–100 while on Wi-Fi, -1 unknown
    // NetworkManager's verdict: full, limited, portal, none or unknown.
    // Real only while its connectivity check is on (Debian's
    // network-manager-config-connectivity-debian); without it NM just
    // says full.
    property string connectivity: "unknown"
    property string checkUri: ""       // the check's URL: a sign-in page intercepts it

    readonly property bool wireless: netType.indexOf("wireless") !== -1
    readonly property string netIcon: vpnOn ? "󰦝"
        : wireless ? (wifiSignal < 0 ? "󰤨" : wifiSignal < 20 ? "󰤯" : wifiSignal < 40 ? "󰤟"
                      : wifiSignal < 60 ? "󰤢" : wifiSignal < 80 ? "󰤥" : "󰤨")
        : netType.indexOf("ethernet") !== -1 ? "󰈀"
        : "󰤭"
    readonly property bool online: netName !== ""
    // connected, but the network wants a login page first (hotel, café)
    readonly property bool signInNeeded: online && connectivity === "portal"
    // connected to something that doesn't reach the internet
    readonly property bool noInternet: online && (connectivity === "limited" || connectivity === "none")

    property var _prev: ({ idle: 0, total: 0 })

    // /proc and /sys answer a plain read: no process, no shell
    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
            const idle = f[3] + (f[4] || 0)
            const total = f.reduce((a, b) => a + b, 0)
            const dIdle = idle - root._prev.idle
            const dTotal = total - root._prev.total
            if (root._prev.total > 0 && dTotal > 0)
                root.cpu = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)))
            root._prev = { idle: idle, total: total }
        }
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: {
            const t = text()
            const total = parseInt((t.match(/MemTotal:\s+(\d+)/) ?? [])[1])
            const avail = parseInt((t.match(/MemAvailable:\s+(\d+)/) ?? [])[1])
            if (total > 0)
                root.mem = 100 * (1 - avail / total)
        }
    }
    // a laptop's battery, once the slow check below has found its folder
    property string batDir: ""
    readonly property bool hasBattery: batDir !== ""
    FileView {
        id: batCapacity
        path: root.batDir !== "" ? root.batDir + "/capacity" : ""
        onLoaded: root.battery = parseInt(text()) || 0
    }
    FileView {
        id: batStatus
        path: root.batDir !== "" ? root.batDir + "/status" : ""
        onLoaded: root.batteryCharging = text().trim() === "Charging"
    }
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            statFile.reload()
            memFile.reload()
            if (root.batDir !== "") {
                batCapacity.reload()
                batStatus.reload()
            }
        }
    }

    // The slow things, one process a minute: disk use, dunst's paused
    // state (it only changes through the bar's own toggle, which rechecks
    // at once), and where the caps-lock LEDs and the battery live.
    Process {
        id: slowProc
        command: ["sh", "-c",
            "df --output=pcent / | tail -n1; echo ===; " +
            "dunstctl is-paused 2>/dev/null || echo false; echo ===; " +
            "ls /sys/class/leds/*capslock/brightness 2>/dev/null; echo ===; " +
            "for b in /sys/class/power_supply/BAT*; do [ -r \"$b/capacity\" ] && echo \"$b\" && break; done; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("===\n")
                const d = parseInt(parts[0])
                if (!isNaN(d))
                    root.disk = d
                root.dndOn = (parts[1] ?? "").trim() === "true"
                const leds = (parts[2] ?? "").trim().split("\n").filter(l => l !== "")
                if (leds.join() !== root.capsPaths.join())
                    root.capsPaths = leds
                root.batDir = (parts[3] ?? "").trim()
            }
        }
    }
    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: slowProc.running = true
    }

    property bool capsOn: false
    property bool dndOn: false

    // caps lock: the keyboards' LED files (no X server to ask on
    // Wayland), one reader per LED, any lit one counts
    property var capsPaths: []
    property var _capsLit: ({})
    Instantiator {
        id: capsLeds
        model: root.capsPaths
        delegate: FileView {
            required property string modelData
            path: modelData
            onLoaded: {
                root._capsLit[modelData] = text().trim() !== "0"
                root.capsOn = root.capsPaths.some(p => root._capsLit[p] === true)
            }
        }
    }
    Timer {
        interval: 1000
        running: root.capsPaths.length > 0
        repeat: true
        onTriggered: {
            for (let i = 0; i < capsLeds.count; i++)
                capsLeds.objectAt(i).reload()
        }
    }

    // mic mute straight from Pipewire: the default source, when it's a
    // real input and not a monitor of the speakers
    readonly property var micNode: Pipewire.defaultAudioSource?.type === PwNodeType.AudioSource
                                   ? Pipewire.defaultAudioSource : null
    PwObjectTracker { objects: [root.micNode] }
    readonly property bool micMuted: micNode?.audio?.muted ?? false

    // recheck dunst right after a toggle instead of waiting out the minute
    Timer {
        id: dndRefresh
        interval: 300
        onTriggered: slowProc.running = true
    }

    function toggleMicMute() {
        if (micNode?.audio)
            micNode.audio.muted = !micNode.audio.muted
        else
            Quickshell.execDetached(["pactl", "set-source-mute", "@DEFAULT_SOURCE@", "toggle"])
    }

    function toggleDnd() {
        Quickshell.execDetached(["dunstctl", "set-paused", "toggle"])
        dndOn = !dndOn
        dndRefresh.restart()
    }
    function popNotification() {
        // replaying must always show something: leave DND first, and say so
        // when the history is empty instead of silently doing nothing
        Quickshell.execDetached(["sh", "-c",
            "dunstctl set-paused false; " +
            "if [ \"$(dunstctl count history)\" -eq 0 ]; then " +
            "notify-send -a dunst -t 2000 'Notifications' 'History is empty'; " +
            "else dunstctl history-pop; fi"])
        dndRefresh.restart()
    }

    // every change NetworkManager announces → one refresh (debounced: a
    // connect fires a burst of lines)
    Process {
        id: netMonitor
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser {
            onRead: line => netDebounce.restart()
        }
        onExited: netMonitorRetry.restart()
    }
    Timer {
        id: netMonitorRetry
        interval: 5000
        onTriggered: {
            netMonitor.running = true
            netProc.running = true   // catch up on what was missed
        }
    }
    Component.onCompleted: netProc.running = true
    Timer {
        id: netDebounce
        interval: 300
        onTriggered: netProc.running = true
    }
    // signal strength is the one thing the monitor doesn't announce:
    // on Wi-Fi only, one small question every 30 s
    Process {
        id: signalProc
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/^\*:(\d+)/m)
                if (root.wireless && m)
                    root.wifiSignal = parseInt(m[1])
            }
        }
    }
    Timer {
        interval: 30 * 1000
        running: root.wireless
        repeat: true
        onTriggered: signalProc.running = true
    }

    // primary transport + vpn tracked separately: a vpn/wireguard/tun
    // connection rides ON a transport, it isn't one. One process, four
    // sections: active connections, connectivity, the in-use AP's signal
    // (cached scan, no rescan), the connectivity check URL.
    Process {
        id: netProc
        command: ["sh", "-c",
            "nmcli -t -f NAME,TYPE connection show --active; echo ===; " +
            "nmcli networking connectivity; echo ===; " +
            "nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no 2>/dev/null | grep '^\\*' | head -1; echo ===; " +
            "busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager " +
            "org.freedesktop.NetworkManager ConnectivityCheckUri 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("===\n")
                let name = "", type = "", vName = "", vOn = false
                for (const line of (parts[0] ?? "").trim().split("\n")) {
                    const i = line.lastIndexOf(":")
                    if (i <= 0)
                        continue
                    const n = line.slice(0, i), t = line.slice(i + 1)
                    if (t === "loopback")
                        continue
                    if (t === "vpn" || t === "wireguard" || t === "tun") {
                        vOn = true
                        vName = n
                    } else if (name === "") {
                        name = n
                        type = t
                    }
                }
                root.netName = name
                root.netType = type
                root.vpnOn = vOn
                root.vpnName = vName
                root.connectivity = (parts[1] ?? "").trim() || "unknown"
                const sig = parseInt((parts[2] ?? "").trim().split(":")[1])
                root.wifiSignal = type.indexOf("wireless") !== -1 && !isNaN(sig) ? sig : -1
                const uri = (parts[3] ?? "").match(/"(.*)"/)
                root.checkUri = uri ? uri[1] : ""
            }
        }
    }
}
