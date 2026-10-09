import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// App launcher (Super+space, or left-click the Debian swirl): a grid of
// every installed app, centered on screen. Type to search (name, generic
// name, keywords, program); arrows move, Enter launches, Esc clears and
// then closes. Chips narrow it to Apps or Settings (the .desktop
// "Settings" category: display, sound, GTK, power and the like — not the
// broader "System", which also claims terminals and file managers);
// Ctrl+Tab cycles them.
// Actions: the bar's own tools (power menu, keybindings, wallpaper, what's
// running, screen off, updates…) are searchable too, drawn as glyph tiles
// so they read differently from apps. They show up in All once you type,
// and all together under the Actions chip; most just open the popup their
// shortcut opens, over the same IPC.
// With nothing typed the grid is alphabetical, so every app keeps its
// spot. How often and how recently you launch something (launcher-history
// in the config folder) only breaks ties between search matches.
// Icons follow the GTK icon theme: scripts/bar hands it to quickshell
// through QS_ICON_THEME at start.
Popout {
    id: root
    ipcNames: ["launcher"]

    property string query: ""
    property int chip: 0                 // index into chips
    property int selected: 0
    property var history: ({})           // id → {count, last (epoch s)}

    readonly property var chips: ["All", "Apps", "Settings", "Actions"]
    readonly property int columns: 6
    readonly property int cellW: 112
    readonly property int cellH: 100
    readonly property string historyFile: Theme.configDir + "/launcher-history"

    // quickshell fills this in the background after start; the binding
    // follows along, so an early open just shows what's scanned so far
    // nwg-displays only speaks sway/Hyprland and quits on mango: the
    // Displays action stands in for it
    readonly property var apps: DesktopEntries.applications.values.filter(
        a => !a.noDisplay && !/^nwg-displays/.test(a.id))
    readonly property var results: search(apps, actions, query, chip, history)

    // name/keywords feed the same search as apps; run is what Enter does
    // (the launcher has already closed by then)
    readonly property var actions: [
        action("power", "Power menu", "󰐥", "shut down reboot restart log out logout power off",
               () => openPopup("power")),
        action("keybinds", "Keybindings", "󰌌", "keys shortcuts hotkeys help cheatsheet",
               () => openPopup("keybinds")),
        action("wallpaper", "Wallpaper", "󰋩", "background theme colors colours",
               () => openPopup("wallpapers")),
        action("layout", "Layout & tweaks", "󰕰", "tiling gaps borders blur shadows animations opacity bar height scale effects",
               () => openPopup("layouts")),
        action("commands", "Command menu", "󰘳", "quick settings night light keep awake caffeine dnd do not disturb pomodoro timer brightness power profile",
               () => openPopup("commands")),
        action("metrics", "What's running", "󰍛", "task manager processes cpu memory ram kill btop system monitor",
               () => openPopup("metrics")),
        action("weather", "Weather", "󰖐", "forecast temperature location",
               () => openPopup("weather")),
        action("network", "Network", "󰖩", "wifi wi-fi vpn bluetooth ethernet internet",
               () => run(["scripts/network"])),
        action("share-wifi", "Share Wi-Fi", "󰐲", "qr code password guest phone join wifi wi-fi",
               () => run(["scripts/network", "share"])),
        action("displays", "Displays", "󰍹", "monitor screen output resolution scale rotate refresh rate arrange mirror vrr",
               () => openPopup("displays")),
        action("lock", "Lock screen", "󰌾", "lock password away afk matrix",
               () => run(["scripts/lock"])),
        action("screen-off", "Screen off", "󰌢", "monitor display blank",
               () => run(["scripts/screen-off"])),
        // a beat for the launcher to unmap before slurp grabs the screen
        action("screenshot-region", "Screenshot (region)", "󰻛", "capture grab snip select",
               () => Quickshell.execDetached(["sh", "-c", "sleep 0.2; exec \"$0\" region",
                                              Theme.configDir + "/scripts/screenshot"])),
        action("screenshot-full", "Screenshot (full screen)", "󰻛", "capture grab whole screen",
               () => Quickshell.execDetached(["sh", "-c", "sleep 0.2; exec \"$0\" full",
                                              Theme.configDir + "/scripts/screenshot"])),
        action("screenshot-copy", "Screenshot (region to clipboard)", "󰅍", "capture grab snip copy paste clipboard",
               () => Quickshell.execDetached(["sh", "-c", "sleep 0.2; exec \"$0\" copy",
                                              Theme.configDir + "/scripts/screenshot"])),
        action("screenshot-edit", "Screenshot (annotate)", "󰏫", "capture grab snip draw arrow text blur edit swappy markup",
               () => Quickshell.execDetached(["sh", "-c", "sleep 0.2; exec \"$0\" edit",
                                              Theme.configDir + "/scripts/screenshot"])),
        action("updates", "Check for updates", "󰚰", "upgrade apt packages software",
               () => Quickshell.execDetached(["ghostty", "-e", "sh", "-c",
                   "sudo apt update && apt list --upgradable; " +
                   "qs -p \"$0\" ipc call updates check >/dev/null 2>&1; " +
                   "printf '\\ndone - press enter to close '; read _",
                   Theme.configDir + "/quickshell"])),
        action("restart-bar", "Restart bar", "󰑓", "quickshell panel reload",
               () => run(["scripts/bar", "restart"])),
        action("reload", "Reload config", "󰑐", "window manager wm config.conf",
               () => Wm.reloadConfig()),
        action("about", "About this system", "󰋼", "system info fastfetch neofetch version specs hardware",
               () => Quickshell.execDetached(["ghostty", "--hold", "sh", "-c",
                   "fastfetch || echo 'fastfetch is not installed: sudo apt install fastfetch'"]))
    ]

    centered: true
    cardWidth: columns * cellW + 2 * cardPadding
    // sized for every app, not the current matches, so typing doesn't
    // make the card jump
    cardHeight: Math.min(header.height + 12 + Math.ceil(Math.max(apps.length, 1) / columns) * cellH
                         + 12 + footer.height + 2 * cardPadding,
                         fitHeight * 0.85)

    onVisibleChanged: {
        if (!visible)
            return
        field.text = ""
        chip = 0
        selected = 0
        grid.positionViewAtBeginning()
        // after Popout's own focus grab on open
        Qt.callLater(() => field.forceActiveFocus())
    }
    onResultsChanged: selected = 0

    FileView {
        path: root.historyFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const h = {}
            for (const l of text().split("\n")) {
                const f = l.split("\t")
                if (f.length === 3)
                    h[f[2]] = { count: Number(f[0]), last: Number(f[1]) }
            }
            root.history = h
        }
    }

    function action(id, name, glyph, keywords, fn) {
        return { isAction: true, id: "action:" + id, name: name, glyph: glyph,
                 keywords: keywords.split(" "), genericName: "", command: [],
                 categories: [], run: fn, family: familyOf(id) }
    }

    // Action tiles are tinted by family so a grid of them scans like app
    // icons do, but the tints come from the theme: the accent's hue
    // turned by a fixed amount per family (and the alert colour for the
    // ones that end your session), so they re-colour with the wallpaper.
    readonly property var families: [
        { key: "system",  label: "System" },
        { key: "capture", label: "Screenshots" },
        { key: "network", label: "Network" },
        { key: "scene",   label: "Wallpaper & weather" },
        { key: "power",   label: "Session" }
    ]
    // the Actions tab at rest: one family per row group, a label over
    // each, rows padded with blank cells so a group always starts a row
    readonly property bool groupedView: chip === 3 && query === ""
    function grouped(acts) {
        const out = []
        for (const f of families) {
            const items = acts.filter(a => a.family === f.key)
                              .sort((a, b) => a.name.localeCompare(b.name))
            if (!items.length)
                continue
            items[0] = Object.assign({}, items[0], { section: f.label })
            out.push(...items)
            while (out.length % columns)
                out.push({ spacer: true, isAction: false, id: "spacer:" + out.length, name: "" })
        }
        return out
    }
    function familyOf(id) {
        if (/^(power|lock|screen-off)$/.test(id)) return "power"
        if (/^screenshot/.test(id)) return "capture"
        if (/^(network|share-wifi)$/.test(id)) return "network"
        if (/^(weather|wallpaper)$/.test(id)) return "scene"
        return "system"
    }
    function tint(family) {
        if (family === "power")
            return Theme.alert
        const turn = { system: 0, capture: 150, network: 210, scene: 300 }[family] ?? 0
        const a = Theme.accent
        return Qt.hsla((a.hslHue + turn / 360) % 1,
                       Math.max(a.hslSaturation, 0.45),
                       Math.min(Math.max(a.hslLightness, 0.52), 0.66), 1)
    }

    function openPopup(target) {
        Quickshell.execDetached(["qs", "-p", Theme.configDir + "/quickshell",
                                 "ipc", "call", target, "toggle"])
    }

    // a script from the config folder: ["scripts/bar", "restart"]
    function run(argv) {
        Quickshell.execDetached([Theme.configDir + "/" + argv[0]].concat(argv.slice(1)))
    }

    function isSettings(a) {
        return a.categories.includes("Settings")
    }

    // how well one lowercase word matches an app: 0 = not at all
    function wordScore(a, w) {
        const name = a.name.toLowerCase()
        if (name.startsWith(w)) return 100
        if (name.split(/[\s\-_.]+/).some(p => p.startsWith(w))) return 80
        if (name.includes(w)) return 60
        const prog = (a.command[0] ?? "").split("/").pop().toLowerCase()
        if (prog.startsWith(w)) return 50
        const extra = [a.genericName, ...a.keywords].join(" ").toLowerCase()
        if (extra.split(/[\s;,\-]+/).some(p => p.startsWith(w))) return 40
        if (extra.includes(w) || prog.includes(w)) return 25
        return 0
    }

    // launches, fading with time since the last one (half weight a week on)
    function frecency(id, hist) {
        const h = hist[id]
        if (!h) return 0
        const days = (Date.now() / 1000 - h.last) / 86400
        return h.count / (1 + Math.max(days, 0) / 7)
    }

    function search(list, acts, q, chipIndex, hist) {
        const words = q.toLowerCase().split(/\s+/).filter(w => w !== "")
        let pool = list
        if (chipIndex === 1) pool = pool.filter(a => !isSettings(a))
        else if (chipIndex === 2) pool = pool.filter(a => isSettings(a))
        else if (chipIndex === 3) {
            if (!words.length)
                return grouped(acts)
            pool = acts
        }
        // All: apps only until you type, so the resting grid stays apps
        else if (words.length) pool = pool.concat(acts)

        if (!words.length)
            return pool.slice().sort((a, b) => a.name.localeCompare(b.name))

        const scored = []
        for (const a of pool) {
            let s = 0
            for (const w of words) {
                const ws = wordScore(a, w)
                if (!ws) { s = 0; break }
                s += ws
            }
            if (s)
                scored.push({ app: a, s: s, f: frecency(a.id, hist) })
        }
        // ties: your launch history first, then the bar's own actions over
        // apps ("shut" is the power menu before any app with it in its
        // keywords), then A–Z
        scored.sort((x, y) => y.s - x.s || y.f - x.f
                    || (y.app.isAction ? 1 : 0) - (x.app.isAction ? 1 : 0)
                    || x.app.name.localeCompare(y.app.name))
        return scored.map(x => x.app)
    }

    function launch(a) {
        if (!a || a.spacer)
            return
        if (!a)
            return
        remember(a.id)
        root.visible = false
        if (a.isAction)
            a.run()
        else if (a.runInTerminal)
            Quickshell.execDetached(["ghostty", "-e"].concat(a.command))
        else
            a.execute()
    }

    // count + last launch per app id; the whole file is rewritten, one
    // line per app, values passed as arguments (never spliced into sh)
    function remember(id) {
        const h = Object.assign({}, history)
        const prev = h[id] ?? { count: 0, last: 0 }
        h[id] = { count: prev.count + 1, last: Math.floor(Date.now() / 1000) }
        history = h
        const lines = Object.keys(h).map(k => h[k].count + "\t" + h[k].last + "\t" + k)
        Quickshell.execDetached(["sh", "-c", "f=$1; shift; printf '%s\\n' \"$@\" > \"$f\"",
                                 "sh", historyFile].concat(lines))
    }

    function move(d) {
        if (!results.length)
            return
        let i = Math.max(0, Math.min(results.length - 1, selected + d))
        // over the blank cells that pad a group, in the direction of travel
        const step = d < 0 ? -1 : 1
        while (i >= 0 && i < results.length && results[i].spacer)
            i += step
        if (i < 0 || i >= results.length)
            return
        selected = i
        grid.positionViewAtIndex(selected, GridView.Contain)
    }

    Column {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        Rectangle {
            width: parent.width
            height: 36
            radius: 8
            color: Qt.alpha(Theme.fg, 0.06)
            border.width: 1
            border.color: field.activeFocus ? Qt.alpha(Theme.accent, 0.5) : "transparent"

            Txt {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: Theme.accent
                font.pixelSize: 14
            }

            TextInput {
                id: field
                anchors.left: searchIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                selectionColor: Qt.alpha(Theme.accent, 0.4)
                font.family: Theme.fontFamily
                font.pixelSize: 13
                clip: true
                onTextChanged: root.query = text

                Keys.onPressed: event => {
                    const k = event.key
                    const ctrl = event.modifiers & Qt.ControlModifier
                    if (k === Qt.Key_Tab && ctrl || k === Qt.Key_Backtab && ctrl) {
                        root.chip = (root.chip + (k === Qt.Key_Backtab ? root.chips.length - 1 : 1)) % root.chips.length
                    } else if (k === Qt.Key_Right || k === Qt.Key_Tab)
                        root.move(1)
                    else if (k === Qt.Key_Left || k === Qt.Key_Backtab)
                        root.move(-1)
                    else if (k === Qt.Key_Down)
                        root.move(root.columns)
                    else if (k === Qt.Key_Up)
                        root.move(-root.columns)
                    else if (k === Qt.Key_PageDown)
                        root.move(root.columns * Math.max(1, Math.floor(grid.height / root.cellH)))
                    else if (k === Qt.Key_PageUp)
                        root.move(-root.columns * Math.max(1, Math.floor(grid.height / root.cellH)))
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                        root.launch(root.results[root.selected])
                    else if (k === Qt.Key_Escape && text !== "")
                        text = ""
                    else {
                        // typing, and a plain Escape on to Popout (closes)
                        event.accepted = false
                        return
                    }
                    event.accepted = true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: field.text === ""
                    text: "Search apps and actions"
                    color: Qt.alpha(Theme.fg, 0.35)
                    font: field.font
                }
            }
        }

        Row {
            spacing: 6

            Repeater {
                model: root.chips

                Rectangle {
                    id: chipItem
                    required property string modelData
                    required property int index
                    readonly property bool active: root.chip === index
                    width: chipText.implicitWidth + 20
                    height: 24
                    radius: 12
                    color: active ? Theme.accent
                         : chipMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Txt {
                        id: chipText
                        anchors.centerIn: parent
                        text: chipItem.modelData
                        color: chipItem.active ? Theme.bg : Qt.alpha(Theme.fg, 0.8)
                        font.bold: chipItem.active
                    }

                    MouseArea {
                        id: chipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.chip = chipItem.index
                            field.forceActiveFocus()
                        }
                    }
                }
            }
        }
    }

    GridView {
        id: grid
        anchors.top: header.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: root.cellW
        cellHeight: root.groupedView ? root.cellH + 18 : root.cellH
        model: root.results
        currentIndex: root.selected
        highlightFollowsCurrentItem: false

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool current: root.selected === index
            readonly property bool blank: !!cell.modelData.spacer
            width: root.cellW
            height: grid.cellHeight
            visible: !blank

            // the group's label, over its first row
            Txt {
                visible: !!cell.modelData.section
                x: 6
                y: 2
                width: root.columns * root.cellW - 12
                text: cell.modelData.section ?? ""
                color: Qt.alpha(Theme.fg, 0.45)
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                anchors.topMargin: root.groupedView ? 19 : 3
                radius: 10
                color: cell.current ? Qt.alpha(Theme.fg, 0.12) : "transparent"
                border.width: cell.current ? 1 : 0
                border.color: Qt.alpha(Theme.accent, 0.5)
            }

            // the card is scaled as a whole; the icon is drawn at its
            // on-screen size and scaled back down, so it stays sharp
            Item {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.groupedView ? 28 : 12
                width: 44
                height: 44

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 44 * root.s
                    scale: 1 / root.s
                    visible: !cell.modelData.isAction
                    source: cell.modelData.isAction ? ""
                          : Quickshell.iconPath(cell.modelData.icon, "application-x-executable")
                }
            }

            // actions: a tinted tile with the bar's glyph, not an app icon
            Rectangle {
                anchors.fill: icon
                visible: !!cell.modelData.isAction
                readonly property color ink: root.tint(cell.modelData.family)
                radius: 10
                color: Qt.alpha(ink, 0.16)
                border.width: 1
                border.color: Qt.alpha(ink, 0.35)

                Txt {
                    anchors.centerIn: parent
                    text: cell.modelData.glyph ?? ""
                    color: parent.ink
                    font.pixelSize: 22
                }
            }

            Txt {
                anchors.top: icon.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: cell.modelData.name
                color: cell.current ? Theme.accent : Qt.alpha(Theme.fg, 0.85)
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selected = cell.index
                onClicked: root.launch(cell.modelData)
            }
        }

        Txt {
            anchors.centerIn: parent
            visible: root.results.length === 0
            text: root.apps.length === 0 ? "loading apps…" : "No apps match \"" + root.query + "\""
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: 12
        }
    }

    // only when the grid is taller than the card (768p laptops)
    Rectangle {
        visible: grid.contentHeight > grid.height
        anchors.right: grid.right
        anchors.rightMargin: -8
        y: grid.y + grid.visibleArea.yPosition * grid.height
        width: 3
        height: grid.visibleArea.heightRatio * grid.height
        radius: 2
        color: Qt.alpha(Theme.fg, 0.3)
    }

    Txt {
        id: footer
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: "↵ open · arrows move · ctrl+tab " + root.chips[(root.chip + 1) % root.chips.length].toLowerCase()
            + " · esc close"
        color: Qt.alpha(Theme.fg, 0.35)
        font.pixelSize: 10
    }
}
