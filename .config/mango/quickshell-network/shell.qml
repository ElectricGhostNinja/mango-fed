import QtQuick
import Quickshell
import Quickshell.Io

// Network — a small connectivity front-end (nmcli + bluetoothctl
// underneath) in its own quickshell instance, laid out by what you came
// to do:
//   the connection you're on (name, status, Wi-Fi switch) and how it's
//   doing (ping, loss, speed, IP, gateway) — then VPNs — then Wi-Fi you've
//   used before (one click to join) and new networks (inline password) —
//   then Bluetooth (click to connect/disconnect, right-click to forget,
//   "pair new" for PIN-less devices; anything needing a PIN is blueman's
//   job; hidden without an adapter) — then rescan / advanced settings.
// The window sizes to its content, up to 80% of the screen, and scrolls.
ShellRoot {
    FloatingWindow {
        id: win

        title: "Network"
        // laid out at 1080p sizes (440 wide) and scaled as a whole by the
        // bar's popup scale (Theme.popupScale): the popup size slider
        implicitWidth: Math.round(440 * Theme.popupScale)
        // as tall as its content; the share view fits itself into that
        implicitHeight: Math.min(Math.round((content.implicitHeight + 32) * Theme.popupScale),
                                 (screen ? screen.height : 1080) * 0.8)
        color: Theme.bg

        // mango sizes a floating window once, when it maps, so it maps only
        // after the first round of data is in (or after 1.5s regardless):
        // it opens at its real size instead of a header-only strip
        property int _loaded: 0
        readonly property bool ready: _loaded >= 3
        visible: ready
        Timer {
            interval: 1500
            running: !win.ready
            onTriggered: win._loaded = 3
        }

        // closing the window (super+q etc.) must end the process too, or the
        // bar's toggle script sees a headless instance and gets out of sync
        onVisibleChanged: if (!visible && ready) Qt.quit()

        // `scripts/network share` (the launcher's Share Wi-Fi) starts the app
        // straight into the share view
        onReadyChanged: if (ready && Quickshell.env("NETWORK_VIEW") === "share") openShare()
        IpcHandler {
            target: "network"
            function share(): void { win.openShare() }
        }

        property var devices: []    // {dev, type, state, conn}
        property bool wifiOn: false
        property var nets: []       // {inUse, signal, security, ssid, freq}
        property var savedWifi: []  // SSIDs of saved Wi-Fi profiles
        property var savedUuid: ({}) // SSID → profile UUID (profile names often aren't the SSID)
        property var savedNoPw: ({}) // SSID → true: the profile holds no usable password
        property bool scanning: false
        property bool busy: false
        property string status: ""
        property string pwFor: ""   // ssid currently asking for a password

        readonly property string wifiDev: {
            for (const d of devices)
                if (d.type === "wifi") return d.dev
            return ""
        }

        // the connection this machine is using: a connected ethernet/wifi
        // device, the one holding the default route when there are two
        property string defaultDev: ""
        property var addrs: ({})           // dev → {ip, gateway}
        property string connectivity: "unknown"
        readonly property var primary: {
            const up = devices.filter(d => d.state === "connected")
            return up.find(d => d.dev === defaultDev) ?? up[0] ?? null
        }
        readonly property var currentNet: nets.find(n => n.inUse) ?? null
        readonly property var knownNets: nets.filter(n => n.inUse || savedWifi.indexOf(n.ssid) !== -1)
        readonly property var otherNets: nets.filter(n => !n.inUse && savedWifi.indexOf(n.ssid) === -1)

        // ping 1.1.1.1 while the window is open: the one number that says
        // "the connection feels bad"
        property real pingMs: -1
        property int lossPct: -1

        property bool btPresent: false
        property bool btOn: false
        property var btDevices: []  // {mac, name, connected}
        property var btFound: []    // {mac, name} — unpaired, from a scan
        property bool btScanning: false

        Component.onCompleted: refresh(false)

        function refresh(rescan) {
            devProc.running = true
            radioProc.running = true
            savedProc.running = true
            detailsProc.running = true
            tsProc.running = true
            btShowProc.running = true
            btDevsProc.running = true
            scanning = true
            scanProc.command = ["sh", "-c",
                "nmcli -t -f IN-USE,SIGNAL,SECURITY,FREQ,SSID dev wifi list --rescan "
                + (rescan ? "yes" : "no")]
            scanProc.running = true
        }

        // the network a connect is under way for: if it fails wanting a
        // password (a saved profile without one, a changed router password),
        // its inline password field opens — mango runs no password dialog
        // (secret agent) of its own
        property var trying: null

        function connectTo(net) {
            if (net.inUse) {
                run(["nmcli", "d", "disconnect", wifiDev], "disconnecting…")
            } else if (savedUuid[net.ssid] && secured(net) && savedNoPw[net.ssid]) {
                // saved, but without a password it can't work: ask right away
                // instead of letting NetworkManager try and time out
                pwFor = net.ssid
                status = "enter the password for " + net.ssid
            } else if (savedUuid[net.ssid]) {
                trying = net
                run(["nmcli", "--wait", "20", "c", "up", "uuid", savedUuid[net.ssid]],
                    "connecting to " + net.ssid + "…")
            } else if (!secured(net)) {
                run(["nmcli", "--wait", "20", "dev", "wifi", "connect", net.ssid],
                    "connecting to " + net.ssid + "…")
            } else {
                pwFor = net.ssid
            }
        }

        // a saved profile gets the password written into it (WPA3-only
        // routers want SAE, everything else WPA-PSK), so it isn't duplicated;
        // a new network gets a profile made by `wifi connect`. Arguments go
        // in as $1.., never spliced into the shell string.
        function connectPw(ssid, pw) {
            pwFor = ""
            const net = nets.find(n => n.ssid === ssid)
            const uuid = savedUuid[ssid]
            if (uuid) {
                const sec = net ? net.security : ""
                const mgmt = sec.indexOf("WPA3") !== -1 && sec.indexOf("WPA2") === -1
                             && sec.indexOf("WPA1") === -1 ? "sae" : "wpa-psk"
                run(["sh", "-c", "nmcli c modify uuid \"$1\" wifi-sec.key-mgmt \"$2\" wifi-sec.psk \"$3\" " +
                     "&& nmcli --wait 20 c up uuid \"$1\"", "sh", uuid, mgmt, pw],
                    "connecting to " + ssid + "…")
            } else {
                run(["nmcli", "--wait", "20", "dev", "wifi", "connect", ssid, "password", pw],
                    "connecting to " + ssid + "…")
            }
        }

        property var _err: []
        function run(cmd, msg) {
            if (busy)
                return
            busy = true
            status = msg
            _err = []
            actProc.command = cmd
            actProc.running = true
        }

        Process {
            id: actProc
            stderr: SplitParser {
                onRead: line => { if (line.trim() !== "") win._err.push(line.trim()) }
            }
            onExited: (code, st) => {
                win.busy = false
                const err = win._err.length ? win._err[win._err.length - 1] : "failed"
                // a saved network that needs its password (again): ask here
                if (code !== 0 && win.trying && win.secured(win.trying)
                    && /secret|password|timeout|expired/i.test(err)) {
                    win.pwFor = win.trying.ssid
                    win.status = "password needed for " + win.trying.ssid
                } else {
                    win.status = code === 0 ? "done" : err
                }
                win.trying = null
                win.refresh(false)
            }
        }

        // --- state readers (accumulate lines, publish on exit) ---

        property var _devs: []
        Process {
            id: devProc
            command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "d"]
            stdout: SplitParser {
                onRead: line => {
                    const p = line.split(":")
                    if (p.length >= 3 && (p[1] === "ethernet" || p[1] === "wifi"))
                        win._devs.push({ dev: p[0], type: p[1], state: p[2],
                                         conn: p.slice(3).join(":") })
                }
            }
            onRunningChanged: {
                if (running) {
                    win._devs = []
                } else {
                    win.devices = win._devs
                    if (!win.ready) win._loaded++
                }
            }
        }

        Process {
            id: radioProc
            command: ["nmcli", "radio", "wifi"]
            stdout: SplitParser {
                onRead: line => win.wifiOn = (line.trim() === "enabled")
            }
        }

        // default-route device, then address + gateway of every connected
        // ethernet/wifi device, then NetworkManager's connectivity verdict
        Process {
            id: detailsProc
            command: ["sh", "-c",
                "echo \"default:$(ip route show default 2>/dev/null | " +
                "awk '{for (i = 1; i < NF; i++) if ($i == \"dev\") { print $(i + 1); exit }}')\"; " +
                "nmcli -t -f DEVICE,TYPE,STATE d | while IFS=: read -r d t s; do " +
                "  case \"$t:$s\" in ethernet:connected|wifi:connected) ;; *) continue ;; esac; " +
                "  echo \"dev:$d:$(cat /sys/class/net/$d/speed 2>/dev/null)\"; " +
                "  nmcli -g IP4.ADDRESS,IP4.GATEWAY device show \"$d\"; " +
                "done; " +
                "echo \"conn:$(nmcli networking connectivity)\""]
            stdout: StdioCollector {
                onStreamFinished: {
                    const lines = text.split("\n")
                    const addrs = {}
                    for (let i = 0; i < lines.length; i++) {
                        const l = lines[i]
                        if (l.startsWith("default:"))
                            win.defaultDev = l.slice(8)
                        else if (l.startsWith("conn:"))
                            win.connectivity = l.slice(5) || "unknown"
                        else if (l.startsWith("dev:")) {
                            // dev:<name>:<link Mb/s>, then "10.0.0.5/24 | fe80::…"
                            // (first address, no prefix) and the gateway
                            const f = l.split(":")
                            const ip = (lines[i + 1] ?? "").split("|")[0].trim().split("/")[0]
                            addrs[f[1]] = { ip: ip, gateway: (lines[i + 2] ?? "").trim(),
                                            speed: parseInt(f[2]) || 0 }
                            i += 2
                        }
                    }
                    win.addrs = addrs
                }
            }
        }

        Timer {
            interval: 5000
            running: true
            repeat: true
            onTriggered: { detailsProc.running = true; tsProc.running = true }
        }

        Process {
            id: pingProc
            command: ["ping", "-n", "-q", "-c", "5", "-i", "0.2", "-W", "1", "1.1.1.1"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const loss = text.match(/(\d+(?:\.\d+)?)% packet loss/)
                    const rtt = text.match(/= [\d.]+\/([\d.]+)\//)
                    win.lossPct = loss ? Math.round(parseFloat(loss[1])) : -1
                    win.pingMs = rtt ? parseFloat(rtt[1]) : -1
                }
            }
        }

        Timer {
            interval: 4000
            running: win.primary !== null
            repeat: true
            triggeredOnStart: true
            onTriggered: pingProc.running = true
        }

        property var vpns: []   // {name, active}
        property var _saved: ({})
        property var _noPw: ({})
        property var _vpns: []
        // saved profiles: Wi-Fi ones by the SSID they join (a profile named
        // "Wi-Fi connection 1" is still Frontier5408), VPNs by name.
        // Terse nmcli escapes ":" as "\:"; the name/SSID comes last.
        Process {
            id: savedProc
            command: ["sh", "-c",
                "nmcli -t -f UUID,TYPE,ACTIVE,NAME c show | while IFS=: read -r uuid type active name; do " +
                "  case \"$type\" in " +
                "    *wireless*) " +
                "      km=$(nmcli -g 802-11-wireless-security.key-mgmt c show \"$uuid\" 2>/dev/null); " +
                "      fl=$(nmcli -g 802-11-wireless-security.psk-flags c show \"$uuid\" 2>/dev/null); " +
                "      echo \"wifi:$uuid:$km:${fl%% *}:$(nmcli -g 802-11-wireless.ssid c show \"$uuid\")\" ;; " +
                "    vpn|wireguard|tun) echo \"$type:$active:$name\" ;; " +
                "  esac; " +
                "done"]
            stdout: SplitParser {
                onRead: line => {
                    const p = line.split(":")
                    if (p.length < 3)
                        return
                    const type = p[0]
                    if (type === "wifi") {
                        // wifi:<uuid>:<key-mgmt>:<psk-flags>:<ssid>. No
                        // key-mgmt = saved as an open network; psk-flags 1/2
                        // = the password lives in a (missing) agent or nowhere
                        const ssid = p.slice(4).join(":").replace(/\\:/g, ":")
                        if (ssid !== "") {
                            win._saved[ssid] = p[1]
                            if (p[2] === "" || p[3] === "1" || p[3] === "2")
                                win._noPw[ssid] = true
                        }
                        return
                    }
                    const rest = p.slice(2).join(":").replace(/\\:/g, ":")
                    const active = p[1] === "yes"
                    const name = rest
                    if (type === "vpn" || type === "wireguard")
                        win._vpns.push({ name: name, active: active,
                                         external: false })
                    // a "tun" connection is an auto-generated profile for an
                    // externally managed device (tailscale etc.): shown, but
                    // read-only — nmcli can down it but never bring it back
                    else if (type === "tun")
                        win._vpns.push({ name: name, active: active,
                                         external: true })
                }
            }
            onRunningChanged: {
                if (running) {
                    win._saved = {}
                    win._noPw = {}
                    win._vpns = []
                } else {
                    win.savedUuid = win._saved
                    win.savedNoPw = win._noPw
                    win.savedWifi = Object.keys(win._saved)
                    win.vpns = win._vpns
                    if (!win.ready) win._loaded++
                }
            }
        }

        // --- Tailscale (when installed): a first-class VPN row, not the
        // read-only "tailscale0" tun profile NetworkManager auto-creates.
        // Reads need nothing; up/down/exit-node need root OR the operator
        // grant — the first action asks (pkexec) to set that once, then
        // every later toggle is silent.
        property bool tsPresent: false
        property string tsState: ""     // Running / Stopped / NeedsLogin
        property string tsIp: ""
        property string tsHost: ""
        property string tsExit: ""      // hostname of the exit node in use
        property var tsExitNodes: []    // {name, online}
        property int tsOnline: 0
        property string tsAuthUrl: ""
        property bool tsPick: false     // exit-node list expanded
        Process {
            id: tsProc
            command: ["sh", "-c", "command -v tailscale >/dev/null 2>&1 && tailscale status --json 2>/dev/null"]
            stdout: StdioCollector {
                onStreamFinished: {
                    if (text.trim() === "") {
                        win.tsPresent = false
                        return
                    }
                    try {
                        const j = JSON.parse(text)
                        win.tsPresent = true
                        win.tsState = j.BackendState ?? ""
                        win.tsIp = j.TailscaleIPs?.[0] ?? ""
                        win.tsHost = j.Self?.HostName ?? ""
                        win.tsAuthUrl = j.AuthURL ?? ""
                        const peers = Object.values(j.Peer ?? {})
                        win.tsOnline = peers.filter(p => p.Online).length
                        win.tsExitNodes = peers.filter(p => p.ExitNodeOption)
                            .map(p => ({ name: p.HostName, online: !!p.Online }))
                            .sort((a, b) => (b.online - a.online) || a.name.localeCompare(b.name))
                        const ex = peers.find(p => p.ExitNode)
                        win.tsExit = ex ? ex.HostName : ""
                    } catch (e) {
                        win.tsPresent = false
                    }
                }
            }
        }
        // run a tailscale command as this user; on "Access denied" grant the
        // operator role once (pkexec asks) and retry
        function tsRun(args, msg) {
            run(["sh", "-c",
                 'err=$(tailscale "$@" 2>&1) && exit 0; ' +
                 'case "$err" in *"Access denied"*) ' +
                 '  pkexec tailscale set --operator="$USER" && exec tailscale "$@" ;; esac; ' +
                 'printf "%s\\n" "$err" >&2; exit 1', "sh"].concat(args), msg)
        }
        // not logged in: get the login URL from `tailscale up` and open it
        function tsLogin() {
            if (tsAuthUrl !== "") {
                Quickshell.execDetached(["xdg-open", tsAuthUrl])
                return
            }
            run(["sh", "-c",
                 'out=$(timeout 20 tailscale up 2>&1); ' +
                 'case "$out" in *"Access denied"*) ' +
                 '  pkexec tailscale set --operator="$USER" || exit 1; out=$(timeout 20 tailscale up 2>&1) ;; esac; ' +
                 'url=$(printf "%s" "$out" | grep -o "https://login[^[:space:]]*" | head -1); ' +
                 '[ -n "$url" ] && { xdg-open "$url"; exit 0; }; ' +
                 'printf "%s\\n" "$out" >&2; exit 1'], "opening tailscale login…")
        }
        // the NM rows, minus tailscale's own tun profile when tailscale
        // itself is shown
        readonly property var vpnRows: vpns.filter(v => !(tsPresent && /^tailscale/.test(v.name)))

        property var _nets: []
        Process {
            id: scanProc
            stdout: SplitParser {
                onRead: line => {
                    // IN-USE:SIGNAL:SECURITY:FREQ:SSID — SSID last, so any
                    // (escaped) colons in it stay in one piece
                    const p = line.split(":")
                    if (p.length < 5)
                        return
                    const ssid = p.slice(4).join(":").replace(/\\:/g, ":")
                    if (ssid === "")
                        return
                    win._nets.push({ inUse: p[0] === "*", signal: parseInt(p[1]) || 0,
                                     security: p[2], freq: parseInt(p[3]) || 0, ssid: ssid })
                }
            }
            onRunningChanged: {
                if (running) {
                    win._nets = []
                } else {
                    // dedup by ssid, keep strongest AP
                    const best = {}
                    for (const n of win._nets)
                        if (!best[n.ssid] || n.signal > best[n.ssid].signal
                            || n.inUse)
                            best[n.ssid] = n
                    win.nets = Object.values(best)
                        .sort((a, b) => (b.inUse - a.inUse) || (b.signal - a.signal))
                    win.scanning = false
                    if (!win.ready) win._loaded++
                }
            }
        }

        function sigGlyph(s) {
            return s < 20 ? "󰤯" : s < 45 ? "󰤟" : s < 70 ? "󰤢" : s < 88 ? "󰤥" : "󰤨"
        }

        function band(freq) {
            return freq >= 5925 ? "6 GHz" : freq >= 4900 ? "5 GHz" : freq > 0 ? "2.4 GHz" : ""
        }

        function secured(n) {
            return n.security !== "" && n.security !== "--"
        }

        // --- live per-device throughput (only while the window is open) ---

        property var _netPrev: ({})
        property var netRates: ({})   // {dev: {down, up}} in bytes/s

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: speedProc.running = true
        }
        Process {
            id: speedProc
            command: ["cat", "/proc/net/dev"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const now = Date.now()
                    const prev = win._netPrev
                    const next = {}
                    const rates = {}
                    for (const line of text.split("\n")) {
                        const m = line.trim().match(/^(\S+):\s*(.*)$/)
                        if (!m || m[1] === "lo")
                            continue
                        const f = m[2].trim().split(/\s+/)
                        const rx = parseInt(f[0]) || 0
                        const tx = parseInt(f[8]) || 0
                        next[m[1]] = { rx: rx, tx: tx, t: now }
                        if (prev[m[1]]) {
                            const dt = (now - prev[m[1]].t) / 1000
                            if (dt > 0)
                                rates[m[1]] = {
                                    down: Math.max(0, (rx - prev[m[1]].rx) / dt),
                                    up: Math.max(0, (tx - prev[m[1]].tx) / dt) }
                        }
                    }
                    win._netPrev = next
                    win.netRates = rates
                }
            }
        }

        function fmtRate(b) {
            return b < 1024 ? Math.round(b) + " B/s"
                 : b < 1048576 ? (b / 1024).toFixed(b < 102400 ? 1 : 0) + " KB/s"
                 : (b / 1048576).toFixed(1) + " MB/s"
        }
        // keyed by interface name — vpn rows match only when the profile
        // name IS the device (tun/tailscale0), which is exactly right
        function rateText(dev) {
            const r = netRates[dev]
            return r ? "↓ " + fmtRate(r.down) + "  ↑ " + fmtRate(r.up) : ""
        }

        // --- share the Wi-Fi you're on: a QR code a phone scans to join ---
        // The password comes from NetworkManager (your desktop session may
        // read it) and goes to qrencode over stdin — never an argument other
        // users could see in ps, never a file: the PNG comes back base64
        // and lives in memory until the share view closes.

        property bool sharing: false
        property string shareSsid: ""
        property string sharePw: ""
        property string shareQr: ""       // data: URL of the PNG
        property string shareError: ""
        property bool shareShowPw: false
        property string _payload: ""

        function openShare() {
            sharing = true
            shareQr = ""
            sharePw = ""
            shareError = ""
            shareShowPw = false
            shareSsid = currentNet ? currentNet.ssid : ""
            if (wifiDev === "" || !currentNet) {
                shareError = "Not connected to Wi-Fi"
                return
            }
            shareInfoProc.command = ["sh", "-c",
                "u=$(nmcli -g GENERAL.CON-UUID device show \"$1\"); " +
                "echo \"ssid:$(nmcli -g 802-11-wireless.ssid c show \"$u\")\"; " +
                "echo \"km:$(nmcli -g 802-11-wireless-security.key-mgmt c show \"$u\" 2>/dev/null)\"; " +
                "echo \"hidden:$(nmcli -g 802-11-wireless.hidden c show \"$u\")\"; " +
                "echo \"psk:$(nmcli -s -g 802-11-wireless-security.psk c show \"$u\" 2>/dev/null)\"",
                "sh", wifiDev]
            shareInfoProc.running = true
        }

        function closeShare() {
            sharing = false
            shareQr = ""
            sharePw = ""
            _payload = ""
        }

        // the Wi-Fi QR format escapes \ ; , : " with a backslash
        function qrEsc(v) {
            return v.replace(/([\\;,:"])/g, "\\$1")
        }

        Process {
            id: shareInfoProc
            stdout: StdioCollector {
                onStreamFinished: {
                    const f = {}
                    for (const l of text.split("\n")) {
                        const i = l.indexOf(":")
                        if (i > 0)
                            // terse nmcli escapes : and \ with a backslash
                            f[l.slice(0, i)] = l.slice(i + 1).replace(/\\([\\:])/g, "$1")
                    }
                    const ssid = f.ssid || win.shareSsid
                    const open = !f.km
                    win.shareSsid = ssid
                    win.sharePw = open ? "" : (f.psk ?? "")
                    if (!open && win.sharePw === "") {
                        win.shareError = "Couldn't read the saved password for " + ssid
                        return
                    }
                    win._payload = "WIFI:T:" + (open ? "nopass" : "WPA") + ";S:" + win.qrEsc(ssid) + ";"
                        + (open ? "" : "P:" + win.qrEsc(win.sharePw) + ";")
                        + (f.hidden === "yes" ? "H:true;" : "") + ";"
                    qrProc.running = true
                }
            }
        }

        Process {
            id: qrProc
            command: ["sh", "-c", "qrencode -t PNG -s 8 -m 2 -o - | base64 -w0"]
            stdinEnabled: true
            onStarted: {
                write(win._payload)
                stdinEnabled = false      // EOF: qrencode reads until here
            }
            onRunningChanged: if (!running) stdinEnabled = true
            stdout: StdioCollector {
                onStreamFinished: {
                    const b64 = text.trim()
                    if (b64 === "")
                        win.shareError = "Install qrencode to share: sudo apt install qrencode"
                    else if (win.sharing)
                        win.shareQr = "data:image/png;base64," + b64
                }
            }
        }

        // --- the header's words ---

        readonly property string headerName: !primary ? "Not connected"
            : primary.type === "wifi" ? (currentNet ? currentNet.ssid : primary.conn)
            : "Ethernet"
        readonly property string headerIcon: !primary ? "󰤮"
            : primary.type === "wifi" ? sigGlyph(currentNet ? currentNet.signal : 100)
            : "󰈀"
        readonly property string headerStatus: {
            if (!primary)
                return wifiDev === "" ? "no network cable or Wi-Fi"
                     : wifiOn ? "pick a network below" : "Wi-Fi is off"
            if (connectivity === "portal")
                return "sign-in required · click to open the login page"
            if (connectivity === "limited" || connectivity === "none")
                return "connected · no internet"
            const bits = ["connected"]
            if (primary.type === "wifi" && currentNet) {
                if (band(currentNet.freq)) bits.push(band(currentNet.freq))
                bits.push(currentNet.signal + "%")
            } else {
                const mbps = addrs[primary.dev]?.speed ?? 0
                if (mbps > 0)
                    bits.push(mbps >= 1000 ? (mbps / 1000) + " Gbps" : mbps + " Mbps")
            }
            return bits.join(" · ")
        }
        readonly property color headerColor: !primary ? Theme.disabled
            : connectivity === "portal" ? Theme.accent
            : (connectivity === "limited" || connectivity === "none") ? Theme.alert
            : Theme.accent

        // --- bluetooth (bluetoothctl underneath) ---

        Process {
            id: btShowProc
            command: ["sh", "-c", "bluetoothctl show 2>/dev/null"]
            property bool sawController: false
            stdout: SplitParser {
                onRead: line => {
                    if (line.indexOf("Controller ") === 0)
                        btShowProc.sawController = true
                    if (line.trim().indexOf("Powered:") === 0)
                        win.btOn = line.indexOf("yes") !== -1
                }
            }
            onRunningChanged: {
                if (running) sawController = false
                else win.btPresent = sawController
            }
        }

        // "Device <mac> <name…>" lines; known = Paired + Trusted (a device
        // can be either, or both — dedupe by mac); a === marker splits
        // known from connected, then "bat <mac> <pct>" for connected devices
        // that report a battery (headsets, some mice) — one process for all
        property var _btPaired: []
        property var _btConn: []
        property var _btBat: ({})
        property bool _btPastMark: false
        Process {
            id: btDevsProc
            command: ["sh", "-c",
                "bluetoothctl devices Paired 2>/dev/null; " +
                "bluetoothctl devices Trusted 2>/dev/null; echo ===; " +
                "bluetoothctl devices Connected 2>/dev/null; " +
                "for m in $(bluetoothctl devices Connected 2>/dev/null | awk '{ print $2 }'); do " +
                "  b=$(bluetoothctl info \"$m\" 2>/dev/null | sed -n 's/.*Battery Percentage:.*(\\([0-9]*\\)).*/\\1/p'); " +
                "  [ -n \"$b\" ] && echo \"bat $m $b\"; " +
                "done"]
            stdout: SplitParser {
                onRead: line => {
                    if (line.trim() === "===") { win._btPastMark = true; return }
                    const p = line.trim().split(" ")
                    if (p[0] === "bat" && p.length === 3) { win._btBat[p[1]] = parseInt(p[2]); return }
                    if (p[0] !== "Device" || p.length < 3) return
                    const d = { mac: p[1], name: p.slice(2).join(" ") }
                    if (win._btPastMark) win._btConn.push(d.mac)
                    else if (!win._btPaired.some(k => k.mac === d.mac))
                        win._btPaired.push(d)
                }
            }
            onRunningChanged: {
                if (running) {
                    win._btPaired = []
                    win._btConn = []
                    win._btBat = {}
                    win._btPastMark = false
                } else {
                    win.btDevices = win._btPaired.map(d => ({
                        mac: d.mac, name: d.name,
                        connected: win._btConn.indexOf(d.mac) !== -1,
                        battery: win._btBat[d.mac] ?? -1 }))
                }
            }
        }

        // scan for new devices: discover for 8s, then list everything and
        // keep the named, unpaired ones (nameless MACs are noise)
        property var _btAll: []
        Process {
            id: btScanProc
            command: ["sh", "-c",
                "bluetoothctl --timeout 8 scan on >/dev/null 2>&1; " +
                "bluetoothctl devices 2>/dev/null"]
            stdout: SplitParser {
                onRead: line => {
                    const p = line.trim().split(" ")
                    if (p[0] === "Device" && p.length >= 3)
                        win._btAll.push({ mac: p[1], name: p.slice(2).join(" ") })
                }
            }
            onRunningChanged: {
                if (running) {
                    win._btAll = []
                } else {
                    const paired = win.btDevices.map(d => d.mac)
                    win.btFound = win._btAll.filter(d =>
                        paired.indexOf(d.mac) === -1
                        && !/^([0-9A-F]{2}-){5}[0-9A-F]{2}$/i.test(d.name))
                    win.btScanning = false
                }
            }
        }

        function btScan() {
            if (btScanning) return
            btScanning = true
            btFound = []
            btScanProc.running = true
        }

        // some headsets make `connect` exit non-zero (br-connection-refused)
        // after BlueZ already flipped Connected: yes — trust the state, not
        // the exit code
        function btToggleDevice(d) {
            if (d.connected)
                run(["bluetoothctl", "disconnect", d.mac],
                    "disconnecting " + d.name + "…")
            else
                run(["sh", "-c", "bluetoothctl connect " + d.mac + "; sleep 1; " +
                     "bluetoothctl info " + d.mac + " | grep -q 'Connected: yes'"],
                    "connecting " + d.name + "…")
        }

        // right-click on a known device: drop the pairing
        function btForget(d) {
            run(["sh", "-c", "bluetoothctl disconnect " + d.mac + " >/dev/null 2>&1; " +
                 "bluetoothctl remove " + d.mac],
                "forgetting " + d.name + "…")
        }

        // PIN-less pair+trust+connect; devices that want a PIN fail here
        // and belong in blueman
        function btPairNew(d) {
            run(["sh", "-c", "bluetoothctl pair " + d.mac +
                 " && bluetoothctl trust " + d.mac +
                 " && bluetoothctl connect " + d.mac],
                "pairing " + d.name + "…")
            btFound = btFound.filter(f => f.mac !== d.mac)
        }

        // --- UI pieces ---

        component Divider: Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.1)
        }

        // the bar modules' pill: soft fill, brighter on hover, optional glyph
        component SmallButton: Rectangle {
            property string label
            property string glyph: ""
            signal clicked()
            width: btnRow.implicitWidth + 20
            height: 26
            radius: 8
            color: Qt.alpha(Theme.fg, btnMa.containsMouse ? 0.14 : 0.07)
            Behavior on color { ColorAnimation { duration: 150 } }
            Row {
                id: btnRow
                anchors.centerIn: parent
                spacing: 6
                Txt {
                    visible: parent.parent.glyph !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.glyph
                    color: Theme.accent
                    font.pixelSize: 13
                }
                Txt {
                    id: btnText
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent.label
                }
            }
            MouseArea {
                id: btnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: parent.clicked()
            }
        }

        // label / value, twice per row
        component Stat: Item {
            property string label
            property string value
            width: parent.width / 2 - 8
            height: 20
            Txt {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: parent.label
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: 12
            }
            Txt {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: parent.value
                font.pixelSize: 12
            }
        }

        // --- UI ---

        Item {
            width: 440
            height: win.height / Theme.popupScale
            scale: Theme.popupScale
            transformOrigin: Item.TopLeft

            // Escape: cancel an open password prompt first, quit otherwise.
            // Keys on the content root, not a Shortcut (those never fire in
            // this window) — unhandled keys bubble up here from the focused
            // password field, and this holds focus the rest of the time.
            focus: true
            Keys.onEscapePressed: {
                if (win.sharing)
                    win.closeShare()
                else if (win.pwFor !== "")
                    win.pwFor = ""
                else
                    Qt.quit()
            }

            // share view: over everything else while open. The network's
            // name as the heading, the code sized to whatever height the
            // window has (it's only as tall as the list), dark on white
            // because that's what phone cameras read.
            Rectangle {
                id: shareLayer
                anchors.fill: parent
                visible: win.sharing
                z: 10
                color: Theme.bg

                readonly property int qrSize: Math.max(150, Math.min(216, height - 150))

                MouseArea { anchors.fill: parent }   // nothing underneath takes clicks

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 12

                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "󰐲  " + win.shareSsid
                        color: Theme.accent
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: shareLayer.qrSize + 16
                        height: width
                        radius: 8
                        color: "white"

                        Image {
                            anchors.centerIn: parent
                            width: shareLayer.qrSize
                            height: width
                            visible: win.shareQr !== ""
                            source: win.shareQr
                            smooth: false          // crisp modules
                            fillMode: Image.PreserveAspectFit
                        }
                        Txt {
                            anchors.centerIn: parent
                            width: parent.width - 32
                            visible: win.shareQr === ""
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: win.shareError !== "" ? win.shareError : "…"
                            color: win.shareError !== "" ? "#b3261e" : "#555"
                            font.pixelSize: 12
                        }
                    }

                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: win.shareError === ""
                        text: "point a phone camera here to join"
                        color: Qt.alpha(Theme.fg, 0.6)
                        font.pixelSize: 12
                    }

                    // the password on request, selectable to copy
                    TextEdit {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: win.shareShowPw && win.sharePw !== ""
                        readOnly: true
                        selectByMouse: true
                        text: win.sharePw
                        color: Theme.fg
                        selectionColor: Qt.alpha(Theme.accent, 0.4)
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        SmallButton {
                            visible: win.sharePw !== ""
                            glyph: win.shareShowPw ? "󰈉" : "󰈈"
                            label: win.shareShowPw ? "hide password" : "password"
                            onClicked: win.shareShowPw = !win.shareShowPw
                        }
                        SmallButton {
                            label: "back"
                            onClicked: win.closeShare()
                        }
                    }
                }
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: 16
                contentHeight: content.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Column {
                    id: content
                    width: parent.width
                    spacing: 8

                    // the connection you're on
                    Item {
                        width: parent.width
                        height: 48

                        // the media popup's art tile, holding the connection's glyph
                        Rectangle {
                            id: heroIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            height: 44
                            radius: 8
                            color: Qt.alpha(Theme.fg, 0.06)

                            Txt {
                                anchors.centerIn: parent
                                text: win.headerIcon
                                color: win.headerColor
                                font.pixelSize: 22
                            }
                        }

                        Column {
                            anchors.left: heroIcon.right
                            anchors.leftMargin: 12
                            anchors.right: qrBtn.visible ? qrBtn.left
                                         : heroToggle.visible ? wifiLabel.left : parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Txt {
                                width: parent.width
                                text: win.headerName
                                font.pixelSize: 13   // the media popup's title size
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Txt {
                                width: parent.width
                                text: win.headerStatus
                                color: win.connectivity === "portal" || win.connectivity === "limited"
                                       || win.connectivity === "none" ? win.headerColor
                                     : Qt.alpha(Theme.fg, 0.55)
                                elide: Text.ElideRight

                                // sign-in page: any plain-http request lands on it
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: win.connectivity === "portal"
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: Quickshell.execDetached(["xdg-open", "http://neverssl.com"])
                                }
                            }
                        }

                        // share this Wi-Fi as a QR code
                        SmallButton {
                            id: qrBtn
                            visible: win.currentNet !== null
                            anchors.right: wifiLabel.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "󰐲"
                            label: "share"
                            onClicked: win.openShare()
                        }

                        Txt {
                            id: wifiLabel
                            visible: heroToggle.visible
                            anchors.right: heroToggle.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Wi-Fi"
                            color: Qt.alpha(Theme.fg, 0.5)
                        }

                        Toggle {
                            id: heroToggle
                            visible: win.wifiDev !== ""
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: win.wifiOn
                            onToggled: win.run(["nmcli", "radio", "wifi", win.wifiOn ? "off" : "on"],
                                               win.wifiOn ? "Wi-Fi off" : "Wi-Fi on")
                        }
                    }

                    // how it's doing
                    Grid {
                        visible: win.primary !== null
                        width: parent.width
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 4
                        topPadding: 4

                        Stat {
                            label: "Ping"
                            value: win.pingMs >= 0 ? Math.round(win.pingMs) + " ms"
                                 : win.lossPct === 100 ? "no reply" : "…"
                        }
                        Stat {
                            label: "Packet loss"
                            value: win.lossPct >= 0 ? win.lossPct + "%" : "…"
                        }
                        Stat {
                            label: "Receiving"
                            value: win.primary && win.netRates[win.primary.dev]
                                   ? win.fmtRate(win.netRates[win.primary.dev].down) : "…"
                        }
                        Stat {
                            label: "Sending"
                            value: win.primary && win.netRates[win.primary.dev]
                                   ? win.fmtRate(win.netRates[win.primary.dev].up) : "…"
                        }
                        Stat {
                            label: "IP address"
                            value: win.primary ? (win.addrs[win.primary.dev]?.ip || "—") : "—"
                        }
                        Stat {
                            label: "Gateway"
                            value: win.primary ? (win.addrs[win.primary.dev]?.gateway || "—") : "—"
                        }
                    }

                    // the plumbing, small: interface and profile name
                    Txt {
                        visible: win.primary !== null
                        width: parent.width
                        text: win.primary ? win.primary.dev + " · " + win.primary.conn : ""
                        color: Qt.alpha(Theme.fg, 0.35)
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }

                    Divider {}

                    // VPN connections — shield row per saved vpn/wireguard profile
                    SectionLabel {
                        visible: win.tsPresent || win.vpnRows.length > 0
                        text: "VPN"
                    }

                    // Tailscale: name · state, toggle; exit-node picker below
                    // when the tailnet offers any
                    Item {
                        visible: win.tsPresent
                        width: parent.width
                        height: 30

                        Txt {
                            id: tsName
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰦝  Tailscale"
                            color: win.tsState === "Running" ? Theme.green : Theme.fg
                            font.pixelSize: 12
                        }
                        Txt {
                            anchors.left: tsName.right
                            anchors.leftMargin: 12
                            anchors.right: tsToggle.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.tsState === "Running"
                                ? win.tsIp + " · " + win.tsOnline + " online"
                                  + (win.tsExit !== "" ? " · exit " + win.tsExit : "")
                                  + (win.rateText("tailscale0") !== "" ? "  " + win.rateText("tailscale0") : "")
                                : win.tsState === "NeedsLogin" ? "not logged in — click to log in"
                                : "off"
                            color: win.tsState === "NeedsLogin" ? Theme.accent : Theme.disabled
                            elide: Text.ElideRight
                        }
                        Toggle {
                            id: tsToggle
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: win.tsState === "Running"
                            onColor: Theme.green
                            onToggled: win.tsState === "NeedsLogin" ? win.tsLogin()
                                : win.tsState === "Running" ? win.tsRun(["down"], "tailscale down…")
                                : win.tsRun(["up"], "tailscale up…")
                        }
                    }

                    Item {
                        visible: win.tsPresent && win.tsState === "Running" && win.tsExitNodes.length > 0
                        width: parent.width
                        height: 28

                        Txt {
                            anchors.left: parent.left
                            anchors.leftMargin: 26
                            anchors.verticalCenter: parent.verticalCenter
                            text: "exit node"
                            color: Qt.alpha(Theme.fg, 0.6)
                        }
                        SmallButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: (win.tsExit !== "" ? win.tsExit : "none") + (win.tsPick ? "  󰅃" : "  󰅀")
                            onClicked: win.tsPick = !win.tsPick
                        }
                    }

                    Repeater {
                        model: win.tsPresent && win.tsState === "Running" && win.tsPick
                            ? [{ name: "", online: true }].concat(win.tsExitNodes) : []

                        Rectangle {
                            id: exitRow
                            required property var modelData
                            readonly property bool current: exitRow.modelData.name === win.tsExit
                            width: parent.width
                            height: 28
                            radius: 8
                            color: current ? Qt.alpha(Theme.accent, 0.2)
                                 : exitMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                            Txt {
                                anchors.left: parent.left
                                anchors.leftMargin: 26
                                anchors.verticalCenter: parent.verticalCenter
                                text: exitRow.modelData.name === "" ? "none" : exitRow.modelData.name
                                color: !exitRow.modelData.online ? Theme.disabled
                                     : exitRow.current ? Theme.accent : Theme.fg
                                font.pixelSize: 12
                                font.bold: exitRow.current
                            }
                            Txt {
                                visible: !exitRow.modelData.online
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "offline"
                                color: Theme.disabled
                            }
                            MouseArea {
                                id: exitMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: exitRow.modelData.online && !exitRow.current
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    win.tsPick = false
                                    win.tsRun(["set", "--exit-node=" + exitRow.modelData.name],
                                              exitRow.modelData.name === "" ? "clearing exit node…"
                                              : "exit via " + exitRow.modelData.name + "…")
                                }
                            }
                        }
                    }

                    Repeater {
                        model: win.vpnRows

                        Item {
                            id: vpnRow
                            required property var modelData
                            width: parent.width
                            height: 30

                            Txt {
                                id: vpnName
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰦝  " + vpnRow.modelData.name
                                color: vpnRow.modelData.active ? Theme.green : Theme.fg
                                font.pixelSize: 12
                            }

                            Txt {
                                visible: vpnRow.modelData.active
                                anchors.left: vpnName.right
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: win.rateText(vpnRow.modelData.name)
                                color: Theme.disabled
                            }

                            Txt {
                                visible: vpnRow.modelData.external
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: vpnRow.modelData.active ? "on · external" : "external"
                                color: vpnRow.modelData.active ? Theme.green : Theme.disabled
                            }

                            Toggle {
                                visible: !vpnRow.modelData.external
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                on: vpnRow.modelData.active
                                onColor: Theme.green
                                onToggled: win.run(["nmcli", "c",
                                    vpnRow.modelData.active ? "down" : "up",
                                    "id", vpnRow.modelData.name],
                                    (vpnRow.modelData.active ? "disconnecting " : "connecting ")
                                    + vpnRow.modelData.name + "…")
                            }
                        }
                    }

                    // Wi-Fi: networks you've used before, then new ones
                    SectionLabel {
                        visible: win.wifiDev !== "" && win.wifiOn
                        text: "Known networks"
                    }
                    Txt {
                        visible: win.wifiDev !== "" && win.wifiOn && win.knownNets.length === 0
                        leftPadding: 10
                        text: win.scanning ? "scanning…" : "none in range"
                        color: Theme.disabled
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: win.wifiOn ? win.knownNets : []
                        delegate: netDelegate
                    }

                    SectionLabel {
                        visible: win.wifiDev !== "" && win.wifiOn
                        text: "Other networks"
                    }
                    Txt {
                        visible: win.wifiDev !== "" && win.wifiOn && win.otherNets.length === 0
                        leftPadding: 10
                        text: win.scanning ? "scanning…" : "none found"
                        color: Theme.disabled
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: win.wifiOn ? win.otherNets : []
                        delegate: netDelegate
                    }

                    // Bluetooth — hidden entirely on machines without an adapter
                    Item {
                        visible: win.btPresent
                        width: parent.width
                        height: 30

                        SectionLabel {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            topPadding: 0
                            text: "Bluetooth"
                        }

                        SmallButton {
                            visible: win.btOn
                            anchors.right: btToggle.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            label: win.btScanning ? "scanning…" : "pair new"
                            onClicked: win.btScan()
                        }

                        Toggle {
                            id: btToggle
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            on: win.btOn
                            onToggled: win.run(["bluetoothctl", "power", win.btOn ? "off" : "on"],
                                               win.btOn ? "bluetooth off" : "bluetooth on")
                        }
                    }

                    Repeater {
                        model: win.btPresent && win.btOn ? win.btDevices : []

                        Rectangle {
                            id: btRow
                            required property var modelData
                            width: parent.width
                            height: 32
                            radius: 8
                            color: btRow.modelData.connected ? Qt.alpha(Theme.accent, 0.2)
                                 : btMa.containsMouse ? Qt.alpha(Theme.fg, 0.08)
                                 : "transparent"

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Txt {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: btState.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰂯  " + btRow.modelData.name
                                color: btRow.modelData.connected ? Theme.accent : Theme.fg
                                font.pixelSize: 12
                                font.bold: btRow.modelData.connected
                                elide: Text.ElideRight
                            }
                            Txt {
                                id: btState
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                // battery after "connected" when the device reports one
                                text: btRow.modelData.connected
                                    ? "connected" + (btRow.modelData.battery >= 0 ? " · " + btRow.modelData.battery + "%" : "")
                                    : "paired"
                                color: btRow.modelData.connected
                                    ? (btRow.modelData.battery >= 0 && btRow.modelData.battery <= 15 ? Theme.alert : Theme.green)
                                    : Theme.disabled
                            }
                            MouseArea {
                                id: btMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => mouse.button === Qt.RightButton
                                    ? win.btForget(btRow.modelData)
                                    : win.btToggleDevice(btRow.modelData)
                            }
                        }
                    }

                    Repeater {
                        model: win.btPresent && win.btOn ? win.btFound : []

                        Rectangle {
                            id: btNewRow
                            required property var modelData
                            width: parent.width
                            height: 32
                            radius: 8
                            color: btNewMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Txt {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: btNewTag.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰂱  " + btNewRow.modelData.name
                                color: Qt.alpha(Theme.fg, 0.7)
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Txt {
                                id: btNewTag
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "pair"
                                color: Theme.disabled
                            }
                            MouseArea {
                                id: btNewMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: win.btPairNew(btNewRow.modelData)
                            }
                        }
                    }

                    Divider {}

                    // status on the left, the rarer actions on the right
                    Item {
                        width: parent.width
                        height: 28

                        Txt {
                            anchors.left: parent.left
                            anchors.right: footerButtons.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.status
                            color: win.status.indexOf("fail") !== -1
                                || win.status.indexOf("Error") !== -1 ? Theme.alert : Theme.disabled
                            elide: Text.ElideRight
                        }

                        Row {
                            id: footerButtons
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            SmallButton {
                                visible: win.wifiDev !== ""
                                label: win.scanning ? "scanning…" : "rescan"
                                onClicked: win.refresh(true)
                            }
                            SmallButton {
                                label: "advanced"
                                onClicked: Quickshell.execDetached(["nm-connection-editor"])
                            }
                        }
                    }
                }
            }
        }

        // one Wi-Fi row: signal, name, a second line for connected/saved,
        // lock for secured, inline password for new secured networks
        Component {
            id: netDelegate

            Column {
                id: netRow
                required property var modelData
                readonly property bool asking: win.pwFor === modelData.ssid
                property bool showPw: false
                onAskingChanged: if (!asking) showPw = false
                readonly property bool saved: win.savedWifi.indexOf(modelData.ssid) !== -1
                width: content.width

                Rectangle {
                    width: parent.width
                    height: netRow.modelData.inUse ? 44 : 34
                    radius: 8
                    color: netRow.modelData.inUse ? Qt.alpha(Theme.accent, 0.18)
                         : netMa.containsMouse ? Qt.alpha(Theme.fg, 0.08)
                         : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Txt {
                        id: netSig
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.sigGlyph(netRow.modelData.signal)
                        color: netRow.modelData.inUse ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
                        font.pixelSize: 15
                    }

                    Column {
                        anchors.left: netSig.right
                        anchors.leftMargin: 12
                        anchors.right: lockT.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Txt {
                            width: parent.width
                            text: netRow.modelData.ssid
                            color: netRow.modelData.inUse ? Theme.accent : Theme.fg
                            font.pixelSize: 12
                            font.bold: netRow.modelData.inUse
                            elide: Text.ElideRight
                        }
                        Txt {
                            visible: netRow.modelData.inUse
                            text: "connected · click to disconnect"
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.pixelSize: 10
                        }
                    }

                    Txt {
                        id: lockT
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.secured(netRow.modelData) ? "󰌾" : ""
                        color: Theme.disabled
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: netMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.connectTo(netRow.modelData)
                    }
                }

                // inline password entry for new secured networks
                Item {
                    visible: netRow.asking
                    width: parent.width
                    height: visible ? 38 : 0

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 8
                        color: Qt.alpha(Theme.fg, 0.08)

                        TextInput {
                            id: pwInput
                            anchors.left: parent.left
                            anchors.right: eyeBtn.left
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: netRow.showPw ? TextInput.Normal : TextInput.Password
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            focus: netRow.asking
                            onAccepted: win.connectPw(netRow.modelData.ssid, text)

                            Text {
                                visible: pwInput.text === ""
                                text: "password"
                                color: Theme.disabled
                                font: pwInput.font
                            }
                        }

                        // show / hide what you've typed
                        Rectangle {
                            id: eyeBtn
                            anchors.right: goBtn.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 24
                            radius: 7
                            color: eyeMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : "transparent"
                            Txt {
                                anchors.centerIn: parent
                                text: netRow.showPw ? "󰈉" : "󰈈"
                                color: Qt.alpha(Theme.fg, 0.7)
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: eyeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    netRow.showPw = !netRow.showPw
                                    pwInput.forceActiveFocus()
                                }
                            }
                        }

                        Rectangle {
                            id: goBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            height: 24
                            radius: 7
                            color: Theme.accent
                            Txt {
                                anchors.centerIn: parent
                                text: "join"
                                color: Theme.bg
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: win.connectPw(netRow.modelData.ssid, pwInput.text)
                            }
                        }
                    }
                }
            }
        }
    }
}
