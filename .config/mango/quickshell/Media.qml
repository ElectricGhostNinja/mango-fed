import QtQuick
import Quickshell.Services.Mpris

// Now-playing (MPRIS). Hidden when nothing is playing. Click toggles
// play/pause, scroll skips tracks, right click opens the now-playing
// popup (art, seek, transport, player switcher), middle click dismisses
// that player until it plays again or changes track — the "I'm watching
// this video, stop telling me about it" gesture, which also clears a
// player left paused for days. The bar pill stays
// short — truncated title plus a progress underline when the track
// reports a length (streams don't); full track info and exact times
// live in the popup. Among multiple players the playing one wins;
// the popup can pin a choice (dropped if that player exits).
BarModule {
    id: root

    // popup-pinned player; falls back to auto when it disappears
    property var manual: null
    // middle-clicked players, by bus name; a player leaves the set the
    // moment it plays or changes track
    property var dismissed: ({})
    property int dismissals: 0
    function dismiss(p) {
        dismissed[p.dbusName] = true
        dismissals++
    }
    function undismiss(p) {
        if (!dismissed[p.dbusName])
            return
        delete dismissed[p.dbusName]
        dismissals++
    }
    readonly property var player: {
        void dismissals
        const ps = Mpris.players.values
        if (manual && ps.indexOf(manual) >= 0)
            return manual
        for (let i = 0; i < ps.length; i++)
            if (ps[i].playbackState === MprisPlaybackState.Playing)
                return ps[i]
        for (let i = 0; i < ps.length; i++)
            if (!dismissed[ps[i].dbusName])
                return ps[i]
        return null
    }
    readonly property bool playing: player !== null
        && player.playbackState === MprisPlaybackState.Playing
    // a dismissed player that starts playing elsewhere takes the pill back
    onPlayerChanged: if (player && playing) undismiss(player)

    // false on a bar too narrow for it (Bar.qml)
    property bool allowed: true

    visible: allowed && player !== null && !dismissed[player.dbusName]
        && player.playbackState !== MprisPlaybackState.Stopped

    // MPRIS reports artists as an array, but some players hand over a
    // plain string — normalize instead of assuming .join exists
    readonly property string artistText: {
        const a = player?.trackArtists
        if (!a) return ""
        return Array.isArray(a) ? a.join(", ") : String(a)
    }

    // MPRIS doesn't push position updates — tick it while playing
    property real pos: 0
    readonly property real len: player?.length ?? 0
    readonly property bool timed: len > 0 && isFinite(len)

    Timer {
        running: root.visible && root.playing
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pos = root.player?.position ?? 0
    }
    // re-read immediately on track change / seek while paused
    Connections {
        target: root.player
        function onTrackTitleChanged() {
            root.pos = root.player?.position ?? 0
            root.undismiss(root.player)
        }
        function onPlaybackStateChanged() {
            if (root.player.playbackState === MprisPlaybackState.Playing)
                root.undismiss(root.player)
        }
        function onPositionChanged() { root.pos = root.player?.position ?? 0 }
    }

    function fmt(s) {
        s = Math.max(0, Math.round(s))
        const m = Math.floor(s / 60), r = s % 60
        return (m >= 60 ? Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0")
                        : m) + ":" + String(r).padStart(2, "0")
    }

    icon: playing ? "󰐊" : "󰏤"
    iconColor: Theme.magenta
    label: {
        if (!player)
            return ""
        const t = artistText !== "" ? artistText + " — " + player.trackTitle
                                    : (player.trackTitle ?? "")
        return t.length > 26 ? t.slice(0, 24) + "…" : t
    }
    progress: timed ? Math.min(pos / len, 1) : -1

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            popup.visible = !popup.visible
        } else if (mouse.button === Qt.MiddleButton) {
            dismiss(player)
            popup.visible = false
        } else if (player && player.canTogglePlaying) {
            player.togglePlaying()
        }
    }
    onScrolled: dir => {
        if (!player)
            return
        if (dir > 0 && player.canGoPrevious)
            player.previous()
        else if (dir < 0 && player.canGoNext)
            player.next()
    }

    MediaPopup {
        id: popup
        anchorItem: root
        media: root
    }
}
