import QtQuick
import Quickshell
import Quickshell.Io

// Command menu, in sections:
//   Batteries — anything UPower knows with a battery (laptop, wireless
//     mouse/keyboard, headset…), only when there is one (Batteries.qml)
//   Quick settings — two-line tiles, name over state (QuickTile): power
//     profile, keep awake, microphone, night light, do not disturb,
//     Bluetooth (with an adapter), focus timer (− / + set its length).
//     Filled = on, red = a state you shouldn't forget (mic muted, DND);
//     right-click = the fuller tool (mixer, notification history, network
//     app). Toggles stay open so the change is visible.
//   brightness slider on laptops
//   System — notifications, snapshots (Timeshift, when installed), check
//     updates, keybindings, restart bar, power menu; these close the menu.
// A running focus timer puts its countdown on this module itself —
// glanceable without a dedicated one.
BarModule {
    id: root

    icon: "󰘳"
    iconColor: pomoDone ? Theme.bg
             : pomoRunning ? Theme.accent : Qt.alpha(Theme.fg, 0.7)
    label: pomoRunning ? fmtPomo(pomoLeft) : pomoDone ? "0:00" : ""
    labelColor: pomoDone ? Theme.bg : Theme.fg
    // time's-up alert: the pill itself goes red until acknowledged, so
    // the signal survives DND (which holds the dunst notification back)
    color: pomoDone ? Theme.red
         : hovered ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.07)
    progress: pomoRunning ? pomoLeft / pomoTotal : -1

    onClicked: {
        pomoDone = false
        menu.visible = !menu.visible
    }

    // polled on every open, all read back from the system so a bar
    // restart can't desync the pills: keep-awake is a systemd-inhibit
    // holder process, night light is a running wlsunset
    property string profile: "balanced"
    property bool caffeine: false
    property bool nightLight: false
    property bool hasBacklight: false
    property int brightness: 50
    property bool btPresent: false
    property bool btOn: false
    property bool hasTimeshift: false
    property bool lockIdle: false    // scripts/idle locks before the screen goes off
    property bool lockRain: true     // lock screen style: matrix rain, else blur

    Process {
        id: stateProc
        // one printf, one guaranteed line per field — a missing tool
        // yields an empty line instead of shifting the indices below
        command: ["sh", "-c",
            "printf '%s\\n' " +
            "\"$(powerprofilesctl get 2>/dev/null)\" " +
            "\"$(brightnessctl -m -c backlight 2>/dev/null | head -n1)\" " +
            "\"$(pgrep -f '[w]hy=quickshell-caffeine' >/dev/null && echo awake)\" " +
            "\"$(pgrep -x wlsunset >/dev/null && echo night)\" " +
            "\"$(bluetoothctl show 2>/dev/null | awk '/Powered:/ { print $2; exit }')\" " +
            "\"$(command -v timeshift-launcher >/dev/null && echo timeshift)\" " +
            "\"$(cat '" + Theme.configDir + "/lock-idle' 2>/dev/null)\" " +
            "\"$('" + Theme.configDir + "/scripts/lock' style 2>/dev/null)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                if (root.profileOrder.indexOf(lines[0]) >= 0)
                    root.profile = lines[0]
                const bl = (lines[1] ?? "").split(",")
                root.hasBacklight = bl.length >= 4
                if (root.hasBacklight)
                    root.brightness = parseInt(bl[3]) || root.brightness
                root.caffeine = lines[2] === "awake"
                root.nightLight = lines[3] === "night"
                // "yes"/"no" from a controller; empty = no adapter
                root.btPresent = (lines[4] ?? "") !== ""
                root.btOn = lines[4] === "yes"
                root.hasTimeshift = lines[5] === "timeshift"
                root.lockIdle = lines[6] === "1"
                root.lockRain = lines[7] !== "blur"
            }
        }
    }

    readonly property var profileOrder: ["performance", "balanced", "power-saver"]
    readonly property var profileIcons: ({ performance: "󰓅", balanced: "󰾅", "power-saver": "󰾆" })
    readonly property var profileNames: ({ performance: "Performance", balanced: "Balanced", "power-saver": "Power saver" })

    function toggleBluetooth() {
        root.btOn = !root.btOn
        Quickshell.execDetached(["bluetoothctl", "power", root.btOn ? "on" : "off"])
    }

    function cycleProfile() {
        const next = profileOrder[(profileOrder.indexOf(profile) + 1) % profileOrder.length]
        Quickshell.execDetached(["powerprofilesctl", "set", next])
        profile = next
    }

    // pomodoro: countdown + drain bar live on the pill. Duration edits
    // only while idle: right-click cycles presets, scroll nudges ±5 min.
    property int pomoMinutes: 25
    readonly property var pomoPresets: [15, 25, 45, 60]
    readonly property int pomoTotal: pomoMinutes * 60
    property double pomoEndMs: 0
    property int pomoLeft: 0
    property bool pomoDone: false
    readonly property bool pomoRunning: pomoEndMs > 0

    // end-timestamp + minutes in a plain state file so a running timer
    // (and the duration preference) survives bar restarts; watched, so
    // `echo "0 25" > ~/.config/suckless/pomodoro` stops it from a shell
    function persistPomo() {
        Quickshell.execDetached(["sh", "-c",
            "printf '%s %s\\n' " + Math.round(pomoEndMs) + " " + pomoMinutes +
            " > '" + Theme.configDir + "/pomodoro'"])
    }

    FileView {
        path: Theme.configDir + "/pomodoro"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const parts = text().trim().split(/\s+/)
            const end = parseFloat(parts[0]) || 0
            const mins = parseInt(parts[1]) || 0
            if (mins >= 5 && mins <= 90)
                root.pomoMinutes = mins
            if (end > Date.now()) {
                root.pomoEndMs = end
                root.pomoLeft = Math.round((end - Date.now()) / 1000)
            } else if (end === 0) {
                root.pomoEndMs = 0
            }
            // end in the past: expired while the bar was down — stay idle
        }
    }

    function fmtPomo(s) {
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }
    function togglePomodoro() {
        pomoDone = false
        if (pomoRunning) {
            pomoEndMs = 0
        } else {
            pomoEndMs = Date.now() + pomoTotal * 1000
            pomoLeft = pomoTotal
        }
        persistPomo()
    }
    function cyclePomoPreset() {
        if (pomoRunning) return
        pomoMinutes = pomoPresets[(pomoPresets.indexOf(pomoMinutes) + 1)
                                  % pomoPresets.length]
        persistPomo()
    }
    function nudgePomo(dir) {
        if (pomoRunning) return
        pomoMinutes = Math.min(90, Math.max(5, pomoMinutes + dir * 5))
        persistPomo()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.pomoRunning
        onTriggered: {
            root.pomoLeft = Math.max(0, Math.round((root.pomoEndMs - Date.now()) / 1000))
            if (root.pomoLeft <= 0) {
                root.pomoEndMs = 0
                root.pomoDone = true
                root.persistPomo()
                // chime plays regardless of DND — it's an alarm; the
                // notification lands in dunst history if DND holds it
                Quickshell.execDetached(["paplay", "--volume=40000",
                    "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"])
                Quickshell.execDetached(["notify-send", "-u", "critical",
                    "Pomodoro", "Time's up — take a break"])
            }
        }
    }

    component CommandRow: Rectangle {
        id: rowRect
        required property var modelData

        width: parent.width
        height: 34
        radius: 8
        color: rowMa.containsMouse ? Qt.alpha(Theme.fg, 0.12) : "transparent"

        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            spacing: 10

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: rowRect.modelData.icon
                color: Theme.cyan
                font.pixelSize: 15
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: rowRect.modelData.label
                color: Qt.alpha(Theme.fg, 0.9)
                font.pixelSize: 13
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                menu.visible = false
                rowRect.modelData.run()
            }
        }
    }

    // history home while the Bell is hidden (it only shows during DND)
    NotifyPopup {
        id: notifHistory
        anchorItem: root
    }

    // Super+/ and the Keybindings row below
    KeybindsPopup {
        id: keybinds
        anchorItem: root
    }

    // Super+x (scripts/power) and the Power menu row below
    DisplaysPopup {
        id: displays
        anchorItem: root
    }
    PowerPopup {
        id: power
        anchorItem: root
    }

    Popout {
        id: menu
        ipcNames: ["commands"]
        anchorItem: root
        cardWidth: 350
        cardHeight: col.implicitHeight + 2 * cardPadding

        onVisibleChanged: if (visible) {
            stateProc.running = true
            Batteries.refresh()
        }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6

            // --- Batteries: only when something reports one ---
            SectionLabel {
                visible: Batteries.devices.length > 0
                topPadding: 0
                text: "Batteries"
            }

            Repeater {
                model: Batteries.devices

                Item {
                    id: bat
                    required property var modelData
                    readonly property bool low: Batteries.isLow(modelData) && !modelData.charging
                    readonly property string more: Batteries.detail(modelData)
                    width: parent.width
                    height: more !== "" ? 36 : 24

                    Txt {
                        id: batGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18
                        horizontalAlignment: Text.AlignHCenter
                        text: Batteries.glyph(bat.modelData)
                        color: bat.low ? Theme.red : Theme.cyan
                        font.pixelSize: 15
                    }
                    Column {
                        anchors.left: batGlyph.right
                        anchors.leftMargin: 10
                        anchors.right: batCharge.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Txt {
                            width: parent.width
                            text: bat.modelData.name
                            color: Qt.alpha(Theme.fg, 0.9)
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Txt {
                            visible: bat.more !== ""
                            width: parent.width
                            text: bat.more
                            color: Qt.alpha(Theme.fg, 0.5)
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                    Txt {
                        id: batCharge
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: Batteries.charge(bat.modelData)
                        color: bat.low ? Theme.red
                             : bat.modelData.pct < 0 && bat.modelData.level === "unknown" ? Qt.alpha(Theme.fg, 0.4)
                             : Theme.fg
                        font.pixelSize: 12
                        font.bold: bat.low
                    }
                }
            }

            // --- Quick settings ---
            SectionLabel {
                topPadding: Batteries.devices.length > 0 ? 6 : 0
                text: "Quick settings"
            }

            Grid {
                width: parent.width
                columns: 2
                spacing: 6

                Repeater {
                    model: [
                        { icon: root.profileIcons[root.profile] ?? "󰾅",
                          name: "Power profile",
                          state: root.profileNames[root.profile] ?? root.profile,
                          active: root.profile !== "balanced",
                          run: () => root.cycleProfile() },
                        { icon: "󰅶", name: "Keep awake",
                          state: root.caffeine ? "On" : "Off",
                          active: root.caffeine,
                          run: () => {
                              root.caffeine = !root.caffeine
                              Quickshell.execDetached(["sh", "-c", root.caffeine
                                  ? "systemd-inhibit --what=idle --who=quickshell --why=quickshell-caffeine sleep infinity >/dev/null 2>&1 &"
                                  : "pkill -f '[w]hy=quickshell-caffeine'"])
                          } },
                        { icon: "󰌾", name: "Lock on idle",
                          state: root.lockIdle ? "On" : "Off",
                          active: root.lockIdle,
                          run: () => {
                              root.lockIdle = !root.lockIdle
                              Quickshell.execDetached(["sh", "-c",
                                  'printf "%s\\n" "$1" > "$2" && exec "$3"', "sh",
                                  root.lockIdle ? "1" : "0", Theme.configDir + "/lock-idle",
                                  Theme.configDir + "/scripts/idle"])
                          } },
                        { icon: root.lockRain ? "󰊠" : "󰂵", name: "Lock style",
                          state: root.lockRain ? "Matrix" : "Blur",
                          active: root.lockRain,
                          run: () => {
                              root.lockRain = !root.lockRain
                              Quickshell.execDetached([Theme.configDir + "/scripts/lock", "style",
                                                       root.lockRain ? "rain" : "blur"])
                          } },
                        { icon: Sys.micMuted ? "󰍭" : "󰍬", name: "Microphone",
                          state: Sys.micMuted ? "Muted" : "On",
                          alert: Sys.micMuted,
                          altFn: () => {
                              menu.visible = false
                              Quickshell.execDetached(["pavucontrol", "-t", "4"])
                          },
                          run: () => Sys.toggleMicMute() },
                        { icon: "󱩌", name: "Night light",
                          state: root.nightLight ? "On" : "Off",
                          active: root.nightLight,
                          run: () => {
                              root.nightLight = !root.nightLight
                              Quickshell.execDetached(["sh", "-c", root.nightLight
                                  ? "command -v wlsunset >/dev/null && (wlsunset -t 4500 -T 6500 >/dev/null 2>&1 &) || notify-send -a quickshell 'Night light' 'Install wlsunset: sudo apt install wlsunset'"
                                  : "pkill -x wlsunset"])
                          } },
                        { icon: Sys.dndOn ? "󰂛" : "󰂚", name: "Do not disturb",
                          state: Sys.dndOn ? "On" : "Off",
                          alert: Sys.dndOn,
                          altFn: () => {
                              menu.visible = false
                              notifHistory.visible = true
                          },
                          run: () => Sys.toggleDnd() },
                        root.btPresent ? {
                          icon: root.btOn ? "󰂯" : "󰂲", name: "Bluetooth",
                          state: root.btOn ? "On" : "Off",
                          active: root.btOn,
                          altFn: () => {
                              menu.visible = false
                              Quickshell.execDetached([Theme.configDir + "/scripts/network"])
                          },
                          run: () => root.toggleBluetooth() } : null,
                        { icon: "󰔟", name: "Focus timer",
                          state: root.pomoRunning ? root.fmtPomo(root.pomoLeft) + " left"
                                                  : root.pomoMinutes + " min",
                          active: root.pomoRunning,
                          adjust: root.pomoRunning ? null : dir => root.nudgePomo(dir),
                          run: () => root.togglePomodoro() }
                    ].filter(t => t)
                    QuickTile {}
                }
            }

            TweakSlider {
                visible: root.hasBacklight
                label: "brightness"
                from: 5; to: 100
                value: root.brightness
                suffix: "%"
                applyFn: v => Quickshell.execDetached(
                    ["brightnessctl", "-c", "backlight", "set", v + "%"])
                persistFn: v => {}   // hardware remembers; nothing to persist
            }

            // --- System ---
            SectionLabel { text: "System" }

            Repeater {
                model: [
                    { icon: "󰂚", label: "Notifications",
                      run: () => notifHistory.visible = true },
                    // Butterbian (btrfs + Timeshift): roll back a bad update.
                    // timeshift-launcher asks for the password itself and,
                    // on Wayland, lets root's window onto Xwayland (xhost).
                    root.hasTimeshift ? { icon: "󰁯", label: "Snapshots",
                      run: () => Quickshell.execDetached(["timeshift-launcher"]) } : null,
                    { icon: "󰚰", label: "Check updates",
                      run: () => Quickshell.execDetached(["ghostty", "-e", "sh", "-c",
                          "sudo apt update && apt list --upgradable; " +
                          "qs -p \"$0\" ipc call updates check >/dev/null 2>&1; " +
                          "printf '\\ndone - press enter to close '; read _",
                          Theme.configDir + "/quickshell"]) },
                    { icon: "󰍹", label: "Displays",
                      run: () => displays.visible = true },
                    { icon: "󰌌", label: "Keybindings",
                      run: () => keybinds.visible = true },
                    { icon: "󰑓", label: "Restart bar",
                      run: () => Quickshell.execDetached([Theme.configDir + "/scripts/bar", "restart"]) },
                    { icon: "󰐥", label: "Power menu",
                      run: () => power.visible = true }
                ].filter(r => r)
                CommandRow {}
            }
        }
    }
}
