pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live palette sourced from the bspwm theme switcher. The switcher rewrites
// polybar/colors.ini (and colors.sh) in place on every switch, so watching
// that file re-colors the bar with no restart — polybar itself can be
// retired without breaking this. Defaults are github_dark placeholders.
//
// The polybar palette is smaller than dwm's xresources+ANSI set, so the
// semantic names below collapse onto it: red→alert, yellow→primary,
// blue/green/cyan/magenta→secondary. Cohesive by construction.
Singleton {
    id: root

    // config root = parent of the running quickshell dir, derived rather
    // than hardcoded so vendored copies (openbox etc.) need no path edits
    readonly property string configDir: {
        let sd = String(Quickshell.shellDir ?? "")
        if (sd.startsWith("file://"))
            sd = sd.slice(7)
        return sd.substring(0, sd.lastIndexOf("/"))
    }

    // bar height (px) and element scale, persisted to plain files (like
    // weather-location) so the tweaks sliders survive restarts
    property int barHeight: 42
    property real barUserScale: 1.0

    // both state files attempted (present or not); bars gate their first
    // map on this to appear once at final size (openbox re-clamps docks
    // on resize). The timer failsafe guarantees the bar always maps.
    property int _barStateLoads: 0
    readonly property bool barStateReady: _barStateLoads >= 2
    Timer {
        running: !root.barStateReady
        interval: 1000
        onTriggered: root._barStateLoads = 2
    }

    property color bg: "#0d1117"
    property color altbg: "#161b22"
    property color fg: "#c9d1d9"
    property color border: "#30363d"
    property color primary: "#58a6ff"
    property color secondary: "#8b949e"
    property color alert: "#f85149"
    property color disabled: "#484f58"

    readonly property color accent: primary
    readonly property color selbg: primary
    readonly property color selfg: bg
    readonly property color red: alert
    readonly property color yellow: primary
    readonly property color blue: secondary
    readonly property color green: secondary
    readonly property color cyan: secondary
    readonly property color magenta: secondary

    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    // Resolution-aware base scale from the outputs' logical short side:
    // 1.0 at 1080p, 1.33 at 1440p, 2.0 at unscaled 4K. An output scale set
    // in mango (the proper hi-dpi fix) shrinks the logical size, so this
    // stays at 1.0 there and nothing is scaled twice. The short side keeps
    // portrait monitors from inflating it; with mixed outputs the smallest
    // wins, so the result doesn't depend on output order and no bar is
    // oversized (the scale slider bumps it up if wanted).
    readonly property real autoScale: {
        const screens = Quickshell.screens
        let side = 0
        for (let i = 0; i < screens.length; i++) {
            const edge = Math.min(screens[i].width, screens[i].height)
            if (side === 0 || edge < side)
                side = edge
        }
        return Math.min(Math.max((side || 1080) / 1080, 0.75), 2.5)
    }

    // The bar's inset from the screen edges. Wm.qml sets mango's outer
    // gaps to the same value so windows float with the same margin.
    readonly property int edgeInset: Math.round(8 * autoScale)
    // matches border_radius in config.conf
    readonly property int barRadius: 8

    // In-bar elements follow autoScale × the scale slider. barHeight is a
    // floor: the window grows when scaled modules (26px at 1.0, + inset
    // above + 8px padding) outgrow it.
    readonly property real barScale: autoScale * barUserScale
    readonly property int fontSize: Math.round(13 * barScale)
    readonly property int iconSize: Math.round(15 * barScale)
    readonly property int moduleHeight: Math.round(26 * barScale)
    readonly property int effectiveBarHeight: Math.max(barHeight, moduleHeight + edgeInset + 8)

    // Popups follow the "popup size" slider (tweaks picker, persisted to
    // popup-scale) — not the screen resolution: at 1.0 they're the size
    // they've always been, on any screen. Popout scales each card as a
    // whole (text, icons, rows and layout together), so popups are written
    // at one set of sizes and never need their own scaling.
    property real popupUserScale: 1.0
    readonly property real popupScale: popupUserScale

    FileView {
        path: root.configDir + "/bar-height"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: root._barStateLoads++
        onLoaded: {
            root._barStateLoads++
            const v = parseInt(text())
            if (!isNaN(v))
                root.barHeight = Math.min(Math.max(v, 32), 80)
        }
    }

    FileView {
        path: root.configDir + "/bar-scale"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: root._barStateLoads++
        onLoaded: {
            root._barStateLoads++
            const v = parseFloat(text())
            if (!isNaN(v))
                root.barUserScale = Math.min(Math.max(v, 0.7), 2.0)
        }
    }

    // not part of barStateReady: popups aren't open at start
    // the Tags strip shows which apps sit on each tag (layout picker toggle)
    property bool tagIcons: false
    FileView {
        path: root.configDir + "/tag-icons"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.tagIcons = text().trim() === "1"
    }

    FileView {
        path: root.configDir + "/popup-scale"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: root.popupUserScale = 1.0
        onLoaded: {
            const v = parseFloat(text())
            root.popupUserScale = isNaN(v) ? 1.0 : Math.min(Math.max(v, 0.8), 2.0)
        }
    }

    FileView {
        path: root.configDir + "/polybar/colors.ini"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseIni(text())
    }

    function parseIni(t) {
        const map = {}
        for (const line of t.split("\n")) {
            const m = line.match(/^\s*([A-Za-z-]+)\s*=\s*(#[0-9a-fA-F]{3,8})/)
            if (m)
                map[m[1]] = m[2]
        }
        if (map["background"]) bg = map["background"]
        if (map["background-alt"]) altbg = map["background-alt"]
        if (map["foreground"]) fg = map["foreground"]
        if (map["border"]) border = map["border"]
        if (map["primary"]) primary = map["primary"]
        if (map["secondary"]) secondary = map["secondary"]
        if (map["alert"]) alert = map["alert"]
        if (map["disabled"]) disabled = map["disabled"]
    }
}
