pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tag state + control — mango backend. `mmsg watch all-monitors` streams
// one JSON line per compositor state change (tags, focus, layout, title)
// and emits a snapshot on connect, so this is the whole read side: no
// polling, no WM patch. Actions go through `mmsg dispatch`. mmsg needs
// MANGO_INSTANCE_SIGNATURE; scripts/mango-ipc fills it in when the bar
// was started outside the compositor's environment.
Singleton {
    id: root

    property int seltags: 1
    property int occtags: 0
    property int urgtags: 0
    property int tagCount: 9
    property string title: ""
    property string monitor: ""     // focused output name (dispatch target)

    // Tags are per monitor in mango, so every output has its own state and
    // each bar shows its own (the properties above are the focused one's).
    property var mons: ({})   // name -> {seltags, occtags, urgtags, tagCount, title, layoutIndex}
    readonly property var _none: ({ seltags: 1, occtags: 0, urgtags: 0, tagCount: 9, title: "", layoutIndex: 0 })
    function of(name) { return mons[name] ?? mons[monitor] ?? _none }
    property bool identifyOutputs: false   // Displays card: name on every screen

    readonly property string ipc: Theme.configDir + "/scripts/mango-ipc"
    function dispatch(cmd) { Quickshell.execDetached([ipc, "dispatch", cmd]) }

    // --- layout: mirrors layouts[] in mango's src/layout/layout.h (symbol
    // is what the IPC reports; name is what setlayout takes). mfact and
    // nmaster flags mark the layouts whose arrange honours them. ---
    readonly property var layouts: [
        { name: "tile",              symbol: "T",  glyph: "󰙀", mfact: true,  nmaster: true  },
        { name: "scroller",          symbol: "S",  glyph: "󰕭", mfact: false, nmaster: false },
        { name: "grid",              symbol: "G",  glyph: "󰝘", mfact: false, nmaster: false },
        { name: "monocle",           symbol: "M",  glyph: "󰕮", mfact: false, nmaster: false },
        { name: "deck",              symbol: "K",  glyph: "󱇙", mfact: true,  nmaster: true  },
        { name: "center tile",       symbol: "CT", glyph: "󰕬", mfact: true,  nmaster: true  },
        { name: "right tile",        symbol: "RT", glyph: "󰙀", mfact: true,  nmaster: true  },
        { name: "vert scroller",     symbol: "VS", glyph: "󱒉", mfact: false, nmaster: false },
        { name: "vert tile",         symbol: "VT", glyph: "󱒈", mfact: true,  nmaster: true  },
        { name: "vert grid",         symbol: "VG", glyph: "󰕯", mfact: false, nmaster: false },
        { name: "vert deck",         symbol: "VK", glyph: "󱇚", mfact: true,  nmaster: true  },
        { name: "dwindle",           symbol: "DW", glyph: "󰕴", mfact: false, nmaster: false },
        { name: "fair",              symbol: "F",  glyph: "󰕫", mfact: false, nmaster: false },
        { name: "vert fair",         symbol: "VF", glyph: "󰪷", mfact: false, nmaster: false }
    ]
    // setlayout wants the snake_case name; the table shows a spaced one
    readonly property var layoutIds: ["tile", "scroller", "grid", "monocle", "deck",
        "center_tile", "right_tile", "vertical_scroller", "vertical_tile",
        "vertical_grid", "vertical_deck", "dwindle", "fair", "vertical_fair"]
    property int layoutIndex: 0

    // desktop tweaks. mango exposes no getters for these, and its setters
    // are relative (setmfact +0.05, incnmaster +1) or config options
    // (setoption gappih N), so the bar keeps the authoritative value: gaps
    // from the mango-gaps state file (re-applied on start, like dwm's),
    // mfact/nmaster from config.conf's defaults, then tracked locally.
    property int gaps: 5
    property int mfact: 55
    property int nmaster: 1

    // effects: blur / shadows / animations toggles, plus border width and
    // unfocused-window opacity sliders, all set live by the picker
    // (setoption) and persisted to mango-effects so they survive a bar
    // restart and a config reload (which resets setoption values). No
    // file = config.conf's values, which these defaults mirror; nothing
    // is pushed to the compositor until the user has touched a control.
    property bool blur: false
    property bool shadows: true
    property bool animations: true
    property int borderpx: 2
    property int unfocusedOpacity: 100   // percent; 100 = no dimming
    property bool effectsFromFile: false
    function applyEffects() {
        if (!effectsFromFile) return
        dispatch("setoption,blur," + (blur ? 1 : 0))
        dispatch("setoption,shadows," + (shadows ? 1 : 0))
        dispatch("setoption,animations," + (animations ? 1 : 0))
        dispatch("setoption,borderpx," + borderpx)
        dispatch("setoption,unfocused_opacity," + (unfocusedOpacity / 100).toFixed(2))
    }
    function persistEffects() {
        Quickshell.execDetached(["sh", "-c",
            "printf 'blur=%s\\nshadows=%s\\nanimations=%s\\nborderpx=%s\\nunfocused_opacity=%s\\n' "
            + (blur ? 1 : 0) + " " + (shadows ? 1 : 0) + " " + (animations ? 1 : 0)
            + " " + borderpx + " " + unfocusedOpacity
            + " > '" + Theme.configDir + "/mango-effects'"])
    }
    function setEffect(name, on) {
        root[name] = on
        effectsFromFile = true
        applyEffects()
        persistEffects()
    }
    // slider paths: applied live while dragging, persisted on release
    function setBorder(v) {
        borderpx = v
        effectsFromFile = true
        dispatch("setoption,borderpx," + v)
    }
    function setUnfocusedOpacity(pct) {
        unfocusedOpacity = pct
        effectsFromFile = true
        dispatch("setoption,unfocused_opacity," + (pct / 100).toFixed(2))
    }

    function setLayout(i, mon) { dispatchOn(mon, "setlayout," + layoutIds[i]) }
    function cycleLayout(dir, mon) {
        setLayout(((of(mon).layoutIndex + dir) % layouts.length + layouts.length) % layouts.length, mon)
    }
    function applyGaps(v) {
        // "window gap" = inner gaps
        dispatch("setoption,gappih," + v)
        dispatch("setoption,gappiv," + v)
        applyOuterGaps()
    }
    // outer gaps = the bar's edge inset (Theme.edgeInset, scaled to the
    // screen), so windows float off the edges exactly like the bar does
    function applyOuterGaps() {
        dispatch("setoption,gappoh," + Theme.edgeInset)
        dispatch("setoption,gappov," + Theme.edgeInset)
    }
    Connections {
        target: Theme
        function onEdgeInsetChanged() { root.applyOuterGaps() }
    }
    function setGaps(v) { gaps = v; applyGaps(v) }
    function setMfact(pct) {
        const d = (pct - mfact) / 100
        if (Math.abs(d) < 0.005) return
        mfact = pct
        dispatch("setmfact," + (d > 0 ? "+" : "") + d.toFixed(2))
    }
    function setNmaster(n) {
        let steps = n - nmaster
        nmaster = n
        while (steps > 0) { dispatch("incnmaster,+1"); steps-- }
        while (steps < 0) { dispatch("incnmaster,-1"); steps++ }
    }

    // gaps state file: written by the picker slider, applied on bar start
    // (a config reload resets setoption values; scripts/mango-reload asks
    // for a re-apply through the "wm" IpcHandler in shell.qml)
    FileView {
        path: Theme.configDir + "/mango-gaps"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text())
            if (!isNaN(v)) { root.gaps = v; root.applyGaps(v) }
        }
    }

    // effects state file, same lifecycle as the gaps one
    FileView {
        path: Theme.configDir + "/mango-effects"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            for (const line of text().split("\n")) {
                const [k, v] = line.split("=")
                const val = (v ?? "").trim()
                if (["blur", "shadows", "animations"].indexOf(k) >= 0)
                    root[k] = val === "1"
                else if (k === "borderpx" && !isNaN(parseInt(val)))
                    root.borderpx = parseInt(val)
                else if (k === "unfocused_opacity" && !isNaN(parseInt(val)))
                    root.unfocusedOpacity = parseInt(val)
            }
            root.effectsFromFile = true
            root.applyEffects()
        }
    }

    // --- state stream ---

    Process {
        id: watch
        command: [root.ipc, "watch", "all-monitors"]
        running: true
        stdout: SplitParser {
            onRead: line => root.parse(line)
        }
        // compositor restart / socket gone: come back on our own
        onExited: watchRetry.restart()
    }
    Timer {
        id: watchRetry
        interval: 2000
        onTriggered: watch.running = true
    }

    function parse(line) {
        let j
        try { j = JSON.parse(line) } catch (e) { return }
        const list = j.monitors ?? []
        if (list.length === 0) return
        const next = {}
        for (const m of list) {
            let sel = 0, occ = 0, urg = 0
            const tags = m.tags ?? []
            for (const t of tags) {
                const bit = 1 << ((t.index ?? 1) - 1)
                if (t.is_active) sel |= bit
                if ((t.client_count ?? 0) > 0) occ |= bit
                if (t.is_urgent) urg |= bit
            }
            const li = layouts.findIndex(l => l.symbol === (m.layout_symbol ?? "T"))
            next[m.name ?? ""] = {
                seltags: sel, occtags: occ, urgtags: urg,
                tagCount: tags.length || 9,
                title: m.active_client?.title ?? "",
                layoutIndex: li >= 0 ? li : 0
            }
        }
        mons = next
        const f = list.find(x => x.active) ?? list[0]
        monitor = f.name ?? ""
        const st = next[monitor]
        tagCount = st.tagCount
        seltags = st.seltags
        occtags = st.occtags
        urgtags = st.urgtags
        title = st.title
        layoutIndex = st.layoutIndex
    }

    // --- which apps sit on which tag (the Tags strip's icons) ---
    // mmsg streams every client change; grouped per tag, one entry per app
    // with a count. Runs only while the toggle is on: off, nothing runs.

    property var tagApps: ({})   // output name -> tag index -> [{appid, icon, count}]
    property var _iconCache: ({})
    function appIcon(appid) {
        if (_iconCache[appid] !== undefined) return _iconCache[appid]
        const entry = DesktopEntries.heuristicLookup(appid)
        const icon = entry?.icon ? Quickshell.iconPath(entry.icon, "application-x-executable") : ""
        _iconCache[appid] = icon
        return icon
    }
    Process {
        id: clientsWatch
        command: [root.ipc, "watch", "all-clients"]
        running: Theme.tagIcons
        stdout: SplitParser {
            onRead: line => root.parseClients(line)
        }
        onExited: if (Theme.tagIcons) clientsRetry.restart()
    }
    Timer {
        id: clientsRetry
        interval: 2000
        onTriggered: if (Theme.tagIcons) clientsWatch.running = true
    }
    Connections {
        target: Theme
        function onTagIconsChanged() { if (!Theme.tagIcons) root.tagApps = ({}) }
    }
    function parseClients(line) {
        let j
        try { j = JSON.parse(line) } catch (e) { return }
        const perMon = {}
        for (const c of j.clients ?? []) {
            if (c.is_scratchpad || c.is_namedscratchpad) continue
            const mon = c.monitor ?? ""
            if (!perMon[mon]) perMon[mon] = {}
            const perTag = perMon[mon]
            for (const t of c.tags ?? []) {
                const i = t - 1
                if (!perTag[i]) perTag[i] = []
                const hit = perTag[i].find(a => a.appid === c.appid)
                if (hit) hit.count++
                else perTag[i].push({ appid: c.appid, icon: appIcon(c.appid), count: 1 })
            }
        }
        tagApps = perMon
    }

    // --- actions ---

    // A bar acts on its own output. When that is not the focused one, mango
    // has cross-monitor verbs for tags; for the rest, focus it first (in
    // one shell so the two calls stay in order).
    function elsewhere(mon) { return mon !== undefined && mon !== "" && mon !== monitor }
    function dispatchOn(mon, cmd) {
        if (!elsewhere(mon)) { dispatch(cmd); return }
        Quickshell.execDetached(["sh", "-c",
            '"$0" dispatch "focusmon,$1" && "$0" dispatch "$2"', ipc, mon, cmd])
    }
    function viewTag(i, mon) {
        dispatch(elsewhere(mon) ? "viewcrossmon," + (i + 1) + "," + mon : "view," + (i + 1))
    }
    function toggleViewTag(i) { dispatch("toggleview," + (i + 1)) }
    function sendToTag(i, mon) {
        dispatch(elsewhere(mon) ? "tagcrossmon," + (i + 1) + "," + mon : "tag," + (i + 1))
    }
    function cycleTag(dir, mon) {
        dispatchOn(mon, dir > 0 ? "viewtoright_have_client" : "viewtoleft_have_client")
    }

    function logout() { dispatch("quit") }
    function reloadConfig() { Quickshell.execDetached([Theme.configDir + "/scripts/mango-reload"]) }

    // processes this session can't lose: the metrics card won't offer to
    // end them (it adds the ones every setup shares). mmsg is the bar's own
    // state stream, wl-paste the clipboard history watcher.
    readonly property var sessionProcs: /^(mango|Xwayland|mmsg|swayidle|awww-daemon|wl-paste)$/
    function openPowerMenu() {
        Quickshell.execDetached([Theme.configDir + "/scripts/power"])
    }
}
