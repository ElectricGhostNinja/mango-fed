pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Everything with a battery: the laptop's own, wireless mice and keyboards
// (Logitech receivers, Bluetooth), headsets, controllers — whatever UPower
// knows about. Read from `upower -d`, not Quickshell's UPower service:
// many mice report only a coarse level (full/high/low/critical) with a
// percentage UPower itself marks "should be ignored", and the service
// shows that fake percentage without the level. Polled every 2 minutes
// (and on demand, when the command menu opens).
//
// Also the two things that must happen with no popup open:
//   - one notification when a device runs low (again only after it
//     recovers), so a dying mouse doesn't surprise you
//   - on a laptop at 20% and falling, switch to the power-saver profile;
//     back to what it was once it's charging
Singleton {
    id: root

    // {path, kind, name, pct (-1: no percentage), level, state,
    //  charging, laptop, rate, timeLeft, health}
    property var devices: []
    readonly property var laptop: devices.find(d => d.laptop) ?? null

    function refresh() { proc.running = true }

    Timer {
        interval: 120000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: proc
        command: ["upower", "-d"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    // "Device: …" blocks: 2-space fields, a bare kind line ("mouse",
    // "battery"), then 4-space fields for that kind
    function parse(t) {
        const out = []
        for (const block of t.split(/\n(?=Device: )/)) {
            const head = block.match(/^Device: (\S+)/)
            if (!head || head[1].endsWith("DisplayDevice"))
                continue
            const f = {}
            let kind = ""
            for (const line of block.split("\n")) {
                const k = line.match(/^ {2}([a-z-]+)$/)
                if (k) { kind = k[1]; continue }
                const kv = line.match(/^ {2,4}([a-z -]+):\s+(.*)$/)
                if (kv) f[kv[1].trim()] = kv[2].trim()
            }
            if (kind === "line-power" || kind === "" || f.present === "no")
                continue
            const pctText = f.percentage ?? ""
            const pct = pctText === "" || pctText.includes("ignored") ? -1 : parseFloat(pctText)
            const laptop = kind === "battery" && f["power supply"] === "yes"
            const state = f.state ?? "unknown"
            out.push({
                path: head[1],
                kind: kind,
                name: laptop ? "Battery" : (f.model || kind.replace(/-/g, " ")),
                pct: isNaN(pct) ? -1 : Math.round(pct),
                level: f["battery-level"] ?? "",          // full/high/normal/low/critical/unknown
                state: state,
                charging: state === "charging" || state === "fully-charged" || state === "pending-charge",
                laptop: laptop,
                rate: f["energy-rate"] ?? "",             // "9.4 W"
                timeLeft: f["time to empty"] ?? "",       // "3.2 hours"
                health: f.capacity ?? ""                  // "91.2%"
            })
        }
        // laptop first, then by name
        out.sort((a, b) => (b.laptop - a.laptop) || a.name.localeCompare(b.name))
        devices = out
        warnLow()
        autoSaver()
    }

    // --- words and glyphs for the menu ---

    function glyph(d) {
        return d.laptop ? (d.charging ? "󰂄" : "󰁹")
             : d.kind === "mouse" ? "󰍽"
             : d.kind === "keyboard" ? "󰌌"
             : d.kind === "headset" || d.kind === "headphones" ? "󰋋"
             : d.kind === "gaming-input" ? "󰊴"
             : d.kind === "phone" ? "󰏲"
             : "󰂑"
    }

    function isLow(d) {
        return d.pct >= 0 ? d.pct <= 15 : (d.level === "low" || d.level === "critical")
    }

    // "78%", or the coarse level, or an honest shrug
    function charge(d) {
        if (d.pct >= 0) return d.pct + "%"
        const words = { full: "Full", high: "High", normal: "Good", low: "Low", critical: "Critical" }
        return words[d.level] ?? "no reading"
    }

    // "3.2 hours" → "3 h 12 min"
    function fmtTime(t) {
        const m = t.match(/([\d.]+)\s+(hours?|minutes?|days?)/)
        if (!m) return t
        const mins = Math.round(parseFloat(m[1]) * (m[2].startsWith("h") ? 60 : m[2].startsWith("d") ? 1440 : 1))
        return mins >= 60 ? Math.floor(mins / 60) + " h " + (mins % 60) + " min" : mins + " min"
    }

    // the laptop's extra line: 9.4 W · 3 h 12 min left · health 91%
    function detail(d) {
        const bits = []
        if (d.charging) bits.push(d.state === "fully-charged" ? "charged" : "charging")
        else if (d.laptop && d.timeLeft) bits.push(fmtTime(d.timeLeft) + " left")
        const watts = parseFloat(d.rate)
        if (d.laptop && watts > 0) bits.push(watts.toFixed(1) + " W")
        if (d.laptop && d.health) bits.push("health " + Math.round(parseFloat(d.health)) + "%")
        return bits.join(" · ")
    }

    // --- low-battery warning, once per drop ---
    // The laptop gets a second, last call at 5%: the 15% one is easy to
    // dismiss and forget.

    property var _warned: ({})
    property var _warnedEmpty: ({})
    function warnLow() {
        const next = {}
        const nextEmpty = {}
        for (const d of devices) {
            if (isLow(d) && !d.charging) {
                next[d.path] = true
                if (!_warned[d.path])
                    Quickshell.execDetached(["notify-send", "-a", "quickshell",
                        "-u", d.laptop ? "critical" : "normal", "-i", "battery-caution",
                        d.name + " battery low", charge(d) + " left"])
            }
            if (d.laptop && !d.charging && d.pct >= 0 && d.pct <= 5) {
                nextEmpty[d.path] = true
                if (!_warnedEmpty[d.path])
                    Quickshell.execDetached(["notify-send", "-a", "quickshell",
                        "-u", "critical", "-i", "battery-empty",
                        "Battery almost empty", charge(d) + " left — plug in now"])
            }
        }
        _warned = next
        _warnedEmpty = nextEmpty
    }

    // --- power saver on a low laptop battery ---

    property string _savedProfile: ""   // what to go back to; "" = we didn't switch
    function autoSaver() {
        const b = laptop
        if (!b) return
        if (!b.charging && b.pct >= 0 && b.pct <= 20 && _savedProfile === "") {
            saverProc.running = true
        } else if (b.charging && _savedProfile !== "") {
            Quickshell.execDetached(["powerprofilesctl", "set", _savedProfile])
            _savedProfile = ""
        }
    }

    // switch only if it isn't already power-saver, and remember from what
    Process {
        id: saverProc
        command: ["sh", "-c",
            "p=$(powerprofilesctl get 2>/dev/null) || exit 0; " +
            "[ \"$p\" = power-saver ] && exit 0; " +
            "powerprofilesctl set power-saver && echo \"$p\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const prev = text.trim()
                if (prev !== "") {
                    root._savedProfile = prev
                    Quickshell.execDetached(["notify-send", "-a", "quickshell", "-i", "battery-caution",
                        "Battery low", "Switched to power saver until you plug in"])
                }
            }
        }
    }
}
